# Fedora-KDE application installer

A very simple application installer for Fedora KDE. Point it at an AppImage or any other
executable. It symlinks the file onto your PATH and writes a `.desktop` entry, so the
program runs from the terminal by name and shows up in the KDE launcher.

One bash script, no dependencies.

## bootstrap

```sh
git clone git@github.com:lasse8290/fk-appinstall.git
cd fk-appinstall
chmod +x appinstall.sh
./appinstall.sh -b
```

`-b` copies the script to `~/.local/bin/appinstall` and puts that directory on `PATH` in
your `~/.zshrc`. Open a new shell afterwards or source `~/.zshrc`. Other shells: add it to `PATH` yourself.

## installing applications

```sh
appinstall ~/Downloads/Obsidian.AppImage
```

`Obsidian` in the launcher, `Obsidian` in the terminal. The command keeps the file's own
casing, the launcher entry is lowercased.

```sh
# proper name, icon and tooltip
appinstall -n Obsidian -i ~/pics/obsidian.png -d Notes ~/Downloads/Obsidian.AppImage

# 'Neovim' in the launcher, 'nvim' in the shell, runs in a terminal
appinstall -n Neovim -c nvim -t /opt/nvim/bin/nvim

# menu entry only, nothing on PATH
appinstall --no-symlink -n 'Some GUI' /opt/thing/thing

# replace an install that is already there
appinstall -f -n Obsidian ~/Downloads/Obsidian.AppImage

# for every user on the machine
sudo appinstall -s -n Obsidian /opt/Obsidian.AppImage
```

## options
Designed to mirror the KDE Desktop Entry Specification.
`appinstall --help`:

```
usage: appinstall [opts] <executable>
       appinstall -u <name>
       appinstall -b

  -n NAME    name shown in the launcher (default: the command name, capitalised)
  -c NAME    name typed in the terminal (default: the file's own name, minus .AppImage)
  -e         also drop any other extension, e.g. thing.sh -> thing
  -i ICON    icon file, or the name of one already in the theme
  -d TEXT    comment / tooltip
  -C LIST    categories, e.g. Development;IDE; (default Utility)
  -w CLASS   StartupWMClass, so the window groups under its own icon
  -a SPEC    argument spec: %U %F %u %f
  -t         run in a terminal
  -s         install under /usr/local instead of ~, needs root
  -f         overwrite what is already there
  -u         remove it again
  -b         install this script into ~/.local/bin
  --no-symlink / --no-desktop    do only one half
```

## uninstalling

```sh
appinstall -u obsidian
```

Takes the command name, any casing, with or without a `.desktop` suffix. Removes the
desktop entry, the symlink and the icon. A real file in `~/.local/bin` is never touched.

## structure

```
appinstall.sh      the whole program
tests/run.sh       the test cases
tests/harness.sh   test frameowrk, sandbox and assertions the tests use
```

`run.sh` sources `harness.sh`, then runs each case in a throwaway temp `$HOME`.

## tests

```sh
tests/run.sh          # everything
tests/run.sh icon     # only cases matching 'icon'
```

Runs against a throwaway `$HOME`, so the real one is never touched.

## support

Currently only Fedora KDE is tested/supported.
