mkdir -p /scratch/$USER/.cache
rm -rf ~/.cache
ln -s /scratch/$USER/.cache ~/.cache

# cache via symlink
mkdir -p /scratch/$USER/.cache
rm -rf ~/.cache
ln -s /scratch/$USER/.cache ~/.cache

# uv payloads explicitly on scratch
mkdir -p /scratch/$USER/apps/bin
mkdir -p /scratch/$USER/apps/uv-tools
mkdir -p /scratch/$USER/apps/uv-tool-bin
mkdir -p /scratch/$USER/apps/uv-python

# Add the following to ~/.bashrc
# export PATH="/scratch/$USER/apps/bin:$HOME/.local/bin:$PATH"

# export UV_INSTALL_DIR="/scratch/$USER/apps/bin"
# export UV_TOOL_DIR="/scratch/$USER/apps/uv-tools"
# export UV_TOOL_BIN_DIR="/scratch/$USER/apps/uv-tool-bin"
# export UV_PYTHON_INSTALL_DIR="/scratch/$USER/apps/uv-python"
source ~/.bashrc

# Create cache dir for claude code
mkdir -p /scratch/$USER/claude-share
mkdir -p /scratch/$USER/claude-home

mkdir -p ~/.local/share
ln -sfn /scratch/$USER/claude-share ~/.local/share/claude
ln -sfn /scratch/$USER/claude-home ~/.claude

# Install
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
uv cache dir
uv tool dir
uv tool dir --bin
uv python dir

curl -fsSL https://claude.ai/install.sh | bash
claude --version
