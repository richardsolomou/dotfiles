#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

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

install() {
  app=$1
  cask=${2:-}

cat << EOF

-> Installing ${app}...
EOF

  if [ "x$OS" = "xWindows" ]; then
    scoop install "${app}"
  else
    if [ -z "$cask" ]; then
      brew list "${app}" &>/dev/null || brew install "${app}"
    else
      brew list --cask "${app}" &>/dev/null || brew install --cask "${app}"
    fi
  fi

cat << EOF

-> ${app} installed
EOF
}

install 1password yes
install cmake
install composer
install cowsay
install direnv
install dotenvx/brew/dotenvx
install elixir
install fortune
install flox yes
install fzf
install gh
install git-extras
install go
install google-drive yes
install httpie
install hey
install jq
install libmaxminddb
install libxmlsec1
install linearmouse yes
install llvm
install markdownlint-cli2
install mergiraf
install mprocs
install nvm
install openssl
install orbstack yes
install pngquant
install rbenv
install readline
install ripgrep
install ruff
install rustup
install slack yes
install spaceship
install swiftformat
install swiftlint
install tree
install uv
install vips
install ghostty yes
install wget
install xz
install ykman
install yq
install zlib
install zsh
install zsh-syntax-highlighting
gh extension install seachicken/gh-poi

# Install Rust
if test ! "$(which rustup)"
then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
fi

brew cleanup
rm -f -r /Library/Caches/Homebrew/*

exit 0
