# Setup the credentials for the environment

# ssh into the server.
# Get secrets for gh-token, wandb-token, hf-token
export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret=gh-token)
export HF_TOKEN=$(gcloud secrets versions access latest --secret=hf-token)
export WANDB_API_KEY=$(gcloud secrets versions access latest --secret=wandb-token)

# Set up git credentials with gh-token
git config --global credential.helper store
printf "https://x-access-token:%s@github.com\n" "$GITHUB_TOKEN" > ~/.git-credentials
chmod 600 ~/.git-credentials
