#!/bin/sh
#
# Homebrew
#
# Install Homebrew and all packages defined in the Brewfile.

# Check for Homebrew
if test ! "$(which brew)"
then
  echo "  Installing Homebrew for you."

  # Install the correct homebrew for each OS type
  if test "$(uname)" = "Darwin"
  then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  elif test "$(expr substr "$(uname -s)" 1 5)" = "Linux"
  then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)"
  fi

fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
brew bundle --file="$SCRIPT_DIR/Brewfile"

gh extension install seachicken/gh-poi

# Install Rust via rustup if brew didn't provide it
if test ! "$(which rustup)"
then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
fi

exit 0
