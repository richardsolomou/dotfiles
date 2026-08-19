#!/usr/bin/env bash

if test ! "$(uname)" = "Darwin"
  then
  exit 0
fi

# Ensure Homebrew is in PATH for non-interactive shells (e.g., mosh, rsync over SSH)
if [ ! -f /etc/paths.d/homebrew ]; then
  echo '/opt/homebrew/bin' | sudo tee /etc/paths.d/homebrew > /dev/null
fi