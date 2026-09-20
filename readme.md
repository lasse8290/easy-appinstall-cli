# Fedora-KDE application installer

A very simple application installer for Fedora KDE. Point it at an AppImage, another
executable, or an application archive. It symlinks the executable onto your PATH and writes a
`.desktop` entry, so the
program runs from the terminal by name and shows up in the KDE launcher.

One Bash script using standard Linux utilities. ZIP archives need Info-ZIP `unzip`.
Tar archives need GNU `tar` and the matching decompressor (`gzip`, `bzip2`, or `xz`).
Python is used only to generate test data; the installer does not use it.

## bootstrap

```sh
git clone git@github.com:lasse8290/easy-appinstall-cli.git
cd easy-appinstall-cli
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

## installing archives

```sh
appinstall ~/Downloads/tool.tar.gz
appinstall --install-dir ~/Apps --executable tool/bin/tool ~/Downloads/tool.zip
```

Supports `.zip`, `.tar`, `.tar.gz` / `.tgz`, `.tar.bz2` / `.tbz2`, and `.tar.xz` / `.txz`.
The first example extracts into `~/Programs/tool/`, preserving the archive's directory
structure. The source archive stays in place. Ordinary executable inputs are still linked
in place.

If the archive contains exactly one executable file, that file is selected automatically.
Otherwise, pass `--executable` with its path relative to the archive root. This also works
when the file lacks execute permission. The command name comes from the selected executable;
use `-c` to change it. All the existing launcher and icon options still apply.

Set a default archive destination in `~/.config/app-install/configfile`:

```ini
install_dir=~/Programs
```

`--install-dir DIR` (or `-p DIR`) overrides the config value. If `XDG_CONFIG_HOME` is set,
the config is read from `$XDG_CONFIG_HOME/app-install/configfile`. Without either setting,
the default is `~/Programs`, or `/usr/local/Programs` with `-s`.

Values can contain spaces and may have surrounding single or double quotes. A leading `~/`
expands to your home directory. Relative destinations are resolved from the current directory.
Blank lines and full-line `#` comments are allowed. Shell variables and commands are not expanded.

An existing archive installation requires `-f` to replace. The replacement removes the old
directory and its contents, so keep personal files outside the application directory.
Extraction and executable selection finish before the old directory is replaced.

Archive paths cannot be absolute or contain `..` components. Bash checks archive names and
file types before extraction. Tar links must also use relative paths without `..` components.
ZIP links and special files are rejected. Tar names with control characters or backslashes
are rejected because they cannot be checked directly against the archive listing.

## options
Designed to mirror the KDE Desktop Entry Specification.
`appinstall --help`:

```
usage: appinstall [opts] <executable-or-archive>
       appinstall -u <name>
       appinstall -b

  -n NAME    name shown in the launcher (default: the command name, capitalised)
  -c NAME    name typed in the terminal (default: the file's own name, minus .AppImage)
  -e         also drop any other extension, e.g. thing.sh -> thing
  -p DIR, --install-dir DIR     extract archives under DIR (default ~/Programs)
  --executable PATH            executable path inside the archive
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
Application files, including extracted archive directories, are kept. Delete the relevant
directory under `~/Programs` (or your chosen destination) separately if it is no longer needed.

## structure

```
appinstall.sh      the whole program
tests/run.sh       the test cases
tests/harness.sh   test framework, sandbox and assertions the tests use
tests/make_archive.py  archive test-data generator
tests/make_pngs.py     PNG test-data generator
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

