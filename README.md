# richardsolomou dotfiles

Your dotfiles are how you personalize your system. These are mine.

They're so personal I copied basically all of them from [haacked's dotfiles](https://github.com/haacked/dotfiles) including the approach to install them.

## Install

Clone the repo wherever you like, then run `script/bootstrap`:

```sh
git clone https://github.com/richardsolomou/dotfiles.git
cd dotfiles
script/bootstrap
```

`script/bootstrap` symlinks the appropriate files into your home directory.
The repo is location-agnostic: scripts derive the dotfiles root from their
own path, so you can keep the clone wherever fits your setup.

The main file you'll want to change right off the bat is `zsh/zshrc.symlink`,
which sets up a few paths that'll be different on your particular machine.

`dot` is a simple script that installs some dependencies, sets sane macOS
defaults, and so on. Tweak this script, and occasionally run `dot` from
time to time to keep your environment fresh and up-to-date. You can find
this script in `bin/`.

### ZSH

`~/.zshrc` is managed by this repo via `zsh/zshrc.symlink`. Running
`script/bootstrap` creates the symlink automatically.
