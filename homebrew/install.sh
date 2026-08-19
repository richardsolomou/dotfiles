#!/bin/sh
#
# Homebrew
#
# Install Homebrew, the packages defined in the Brewfile, and the gh extensions
# the git aliases depend on.

if ! command -v brew > /dev/null 2>&1
then
  echo "  Installing Homebrew for you."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
brew bundle --file="$SCRIPT_DIR/Brewfile"

# gh poi backs `git bclean`; gh stack backs the stacked-PR workflow.
for extension in seachicken/gh-poi github/gh-stack
do
  gh extension install "$extension" 2>/dev/null || true
done

exit 0
