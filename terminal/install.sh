#!/bin/sh

export ZSH="$(cd "$(dirname "$0")/.." && pwd -P)"

cp $ZSH/terminal/.tmux.conf ~/.tmux.conf
