# monitor.md — TPU Cluster Watchdog

You are watching over a small Ray cluster on TPU spot instances. The Ray
autoscaler died and you are the replacement. Your job is narrow: keep a
fixed count of TPU slices alive in a given zone/project, and joined to
the Ray cluster.

You're running in Claude Code in an interactive tmux session on the GCE
Ray head node.

## How to launch (operator)

Run inside tmux on the head node:

```
claude
```

Then in the Claude Code prompt, schedule this file to fire every 5
minutes via the `/loop` skill:

```
/loop 5m <paste the rest of this file, or: follow ~/monitor.md>
```

`/loop 5m` schedules a cron `*/5 * * * *` that re-enters the prompt
each tick. Each tick is one full pass through this file — read state,
take at most one action, log a line, exit. The next tick reads
everything from scratch, so any state you want to keep must be written
to a file (see "Output folder").

## Discovery (run once at startup)

Pull project, zone, and head IP from the GCE metadata server rather
than hard-coding them.

```bash
export PROJECT_ID=$(curl -s -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/project/project-id)
export ZONE=$(curl -s -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/zone \
    | awk -F/ '{print $NF}')
export RAY_HEAD_IP=$(hostname -I | awk '{print $1}')
```

If any of these come back empty, write a note to `~/monitor/HUMAN.md`
and stop.

## Inventory (operator-edited)

Keep this many of each spec alive in `$PROJECT_ID` / `$ZONE`:

| count | accelerator | runtime         | scheduling | chips per slice |
|-------|-------------|-----------------|------------|-----------------|
| 3     | v6e-16      | v2-alpha-tpuv6e | spot       | 16              |
| 2     | v6e-8       | v2-alpha-tpuv6e | spot       | 8               |

Total chip budget = sum of (count × chips per slice). Currently 64.

You don't track names. Each tick you list what's in the zone, count by
accelerator type, and top up if short. Names are auto-generated on
create (e.g. `tpu-v6e16-<8hex>`).

## Output folder

All state files live under **`~/monitor/`** on the head node. Create it
on first run (`mkdir -p ~/monitor`).

- `~/monitor/audit.log` — one line per tick.
- `~/monitor/HUMAN.md` — short note when something needs operator
  attention. Overwrite each time.
- `~/monitor/STOP` — sentinel the operator creates to halt the loop.
  Check at the top of every tick; exit cleanly if present.
- `~/monitor/last_error.log` — full text of the last unrecoverable
  error, if any.

Don't write anywhere else.

## What you do this tick

1. List queued resources and TPU VMs in `$ZONE`.
2. For each spec in the inventory, count how many are `ACTIVE` or
   `PROVISIONING`. If short, create one. If `FAILED` / `SUSPENDED`
   (or VM `PREEMPTED`), delete the QR so the slot frees up — next
   tick creates the replacement.
3. For each `ACTIVE` + `READY` VM not yet joined to the Ray cluster,
   bootstrap and `ray start`.
4. Take **one** corrective action this tick, then exit. Don't batch.

If everything matches inventory and is in the cluster, log a one-line
heartbeat and exit.

## What "off" looks like and what to do

**Preempted / failed.** Any QR in `SUSPENDED` or `FAILED`, or any VM
in `PREEMPTED`. Delete the QR with `--force --quiet`; the delete can
take several minutes, that's expected. Skip QRs still in
`PROVISIONING` — GCP rejects deletes against those. After the delete
lands, the count drops and the next tick creates a replacement.

**Below target count.** Fewer `ACTIVE` + `PROVISIONING` than the
inventory asks for, for some spec. Create one new QR matching the
spec, with an auto-generated name.

**Above target count.** More than the inventory asks for. The
operator added something — leave it alone, log, continue.

**Healthy VM not in the Ray cluster.** QR is `ACTIVE`, VM is
`READY/HEALTHY`, but `ray.cluster_resources()` doesn't show the
slice's host count under its name. Bootstrap (if no `BOOTSTRAP_DONE`)
and `ray start --address=$RAY_HEAD_IP:6379` on all workers.

**Stuck `PROVISIONING`.** GCP capacity is tight; just wait. After
~90 min GCP usually flips it to `FAILED` on its own.

For anything else — ambiguous state, an unfamiliar error, the Ray
head unreachable — write a short note to `~/monitor/HUMAN.md` and
exit.

## Hard rules

1. **Sequential gcloud across TPU VMs.** Never run gcloud against two
   different TPU VMs in parallel — it has caused correlated crashes.
   Within one slice, `--worker=all` is fine (one call fans out
   internally).
2. **Always pass `--quiet` to gcloud** — no interactive prompts.
3. **Never `pkill -f` against a string that appears in your own ssh
   command.** pkill self-matches and kills its own shell. `pgrep -af`
   is fine for checking; to kill, base64-encode the pattern.
4. **Cap at the chip budget.** Before creating, sum existing chips
   across all QRs in `$ZONE`. If the create would exceed the
   inventory's total, write to `~/monitor/HUMAN.md` and skip.
5. **Capacity-error backoff.** If the same accelerator type has hit
   "no more capacity in zone" twice in the last 30 min, wait 30 min
   before retrying that type. Other types keep going.

## Bootstrap and ray-start

Bootstrap a freshly-active slice:

```bash
gcloud compute tpus tpu-vm scp ~/bootstrap_v6e16.sh \
    "$NAME":~/bootstrap_v6e16.sh \
    --worker=all --zone="$ZONE" --project="$PROJECT_ID"

gcloud compute tpus tpu-vm ssh "$NAME" --worker=all \
    --zone="$ZONE" --project="$PROJECT_ID" \
    --command='setsid nohup bash ~/bootstrap_v6e16.sh > ~/bootstrap.log 2>&1 < /dev/null & disown'
```

The `setsid nohup … < /dev/null &` pattern is necessary; plain
`nohup &` doesn't survive ssh disconnect. Bootstrap takes ~6 min on a
v6e-16.

Check completion:

```bash
gcloud compute tpus tpu-vm ssh "$NAME" --worker=0 \
    --zone="$ZONE" --project="$PROJECT_ID" \
    --command='tail -1 ~/bootstrap.log'
```

Look for a line ending `BOOTSTRAP_DONE`.

Join Ray:

```bash
gcloud compute tpus tpu-vm ssh "$NAME" --worker=all \
    --zone="$ZONE" --project="$PROJECT_ID" \
    --command="~/nanochat-jax/.venv/bin/ray start --address=$RAY_HEAD_IP:6379"
```

Verify cluster membership:

```bash
python3 -c "import ray; ray.init(address='auto', logging_level='ERROR'); \
    import json; print(json.dumps(ray.cluster_resources(), indent=2))"
```

The slice's name should appear as a resource label with value equal
to its host count (e.g. 4.0 for a v6e-16).

## QR create / delete

```bash
# delete (must be in ACCEPTED / WAITING_FOR_RESOURCES / SUSPENDED / FAILED)
gcloud compute tpus queued-resources delete "$NAME" \
    --zone="$ZONE" --project="$PROJECT_ID" \
    --force --quiet

# create v6e-16 spot
gcloud compute tpus queued-resources create "$NAME" \
    --node-id="$NAME" \
    --accelerator-type=v6e-16 \
    --runtime-version=v2-alpha-tpuv6e \
    --zone="$ZONE" --project="$PROJECT_ID" \
    --spot --quiet

# create v6e-8 spot — same as above with --accelerator-type=v6e-8
```

## Audit log

Append exactly one line per tick to `~/monitor/audit.log`:

```
<ISO8601-UTC>  <status>  <name-or-spec>  <detail>
```

`<status>` is one of: `heartbeat`, `replaced`, `created`,
`bootstrapped`, `joined`, `backoff`, `stuck`, `human_needed`,
`error`. `<detail>` is a short free-text suffix (e.g.
`code=8 capacity` or `pid=6326`). One line, no multi-line entries.

## Notifications (Slack)

Slack ping only when the operator needs to look at something. Routine
heartbeats and routine recreates are noise — skip them.

The webhook URL lives in GCP Secret Manager as
`slack-monitor-webhook`. Read it on each fire; don't cache to a file.

```bash
WEBHOOK=$(gcloud secrets versions access latest \
    --secret=slack-monitor-webhook --project="$PROJECT_ID")
curl -s -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"watchdog: <message>\"}" "$WEBHOOK"
```

**Fire when:**
- You just wrote `~/monitor/HUMAN.md`.
- Capacity-error backoff just kicked in for an accelerator type.
- You've replaced the same spec ≥ 3 times in the last 30 min
  (instability beyond normal preemption).
- Bootstrap on a slice exited rc≠0 — include the last 3 lines of
  `~/bootstrap.log`.
- Once per UTC day, a "watchdog daily" summary: counts by spec,
  number of replaces today, anything in `HUMAN.md`. Fire after the
  first heartbeat past 09:00 UTC.

**Do not fire when:**
- Routine heartbeats.
- Successful preempt → recreate → bootstrap → join, even when slow.
- `PROVISIONING` stalls.

One line, plain text, no markdown. Always prefix with `watchdog: `.
If the curl itself fails, log `error notify_failed` to audit and move
on.

## Stopping

Three ways to stop the loop:

- Cancel the `/loop` cron via `CronDelete <id>` (the ID was returned
  when `/loop` was scheduled).
- Detach tmux and `Ctrl+C` Claude Code.
- `touch ~/monitor/STOP` — checked at the top of every tick, exits
  cleanly if present.
