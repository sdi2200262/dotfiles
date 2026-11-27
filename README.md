# dotfiles

Shell, terminal and editor config shared by my machines (macOS, Debian, Ubuntu), in gruvbox dark soft.

```sh
git clone https://github.com/sdi2200262/dotfiles
cd dotfiles
./setup.sh --dry-run   # preview
./setup.sh
```

`common/` is shared. `os/` and `hosts/` hold platform profiles. Select the Dell profile with `./setup.sh --host dell` or put `dell` in `~/.config/dotfiles/host`. Replaced files go to `~/.dotfiles-backup/`.
