# one line install scripts

This stores convenient installation scripts.


## Codex
```bash
curl -fsSL https://raw.githubusercontent.com/charliezchen/one_line_install_scripts/main/install_codex.sh | sh
```

## Claude Code
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

## uv
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
```

## Credentials on TPU VM
```bash
# Get secrets for gh-token, wandb-token, hf-token
echo "export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret=gh-token)" >> ~/.bashrc
echo "export HF_TOKEN=$(gcloud secrets versions access latest --secret=hf-token)" >> ~/.bashrc
echo "export WANDB_API_KEY=$(gcloud secrets versions access latest --secret=wandb-token)" >> ~/.bashrc
source ~/.bashrc

# Set up git credentials with gh-token
git config --global credential.helper store
printf "https://x-access-token:%s@github.com\n" "$GITHUB_TOKEN" > ~/.git-credentials
chmod 600 ~/.git-credentials
```
