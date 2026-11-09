#!/bin/sh
#
# Git configuration setup
#
# This sets up mergiraf as the default merge tool

# Create the git config directory if it doesn't exist
mkdir -p ~/.config/git

# Check if ~/.config/git/attributes exists
if [ ! -f ~/.config/git/attributes ]; then
  echo "Creating ~/.config/git/attributes and setting up mergiraf..."
  echo "* merge=mergiraf" > ~/.config/git/attributes
  echo "✓ Created ~/.config/git/attributes with mergiraf configuration"
else
  # Check if mergiraf is already configured
  if grep -q "merge=mergiraf" ~/.config/git/attributes; then
    echo "✓ mergiraf is already configured in ~/.config/git/attributes"
  else
    echo "Adding mergiraf configuration to existing ~/.config/git/attributes..."
    echo "* merge=mergiraf" >> ~/.config/git/attributes
    echo "✓ Added mergiraf configuration to ~/.config/git/attributes"
  fi
fi
# Aliases live in git's XDG config rather than an [include] of ~/.gitconfig, because
# sandboxed tools (PostHog's bin/dev-sandbox) may read only the standard config paths.
ln -sfn "$(cd "$(dirname "$0")" && pwd)/aliases.gitconfig" ~/.config/git/config
