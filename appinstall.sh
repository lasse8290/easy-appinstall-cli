#!/usr/bin/env bash
# Put a program on PATH and in the KDE launcher.

set -euo pipefail

# The command is 'appinstall' even while the file is appinstall.sh, so drop
# the extension. -b then installs the copy under the bare name too.
prog=${0##*/}
prog=${prog%.sh}

# Complain on stderr and give up.
die() { echo "$prog: $*" >&2; exit 1; }
# Say what we just did, on stdout.
say() { echo "$prog: $*"; }

# The help text, also shown when there is nothing to install.
usage() {
	cat >&2 <<-EOF
	usage: $prog [opts] <executable>
	       $prog -u <name>
	       $prog -b

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

	examples:
	  # the usual case, a symlink plus a launcher entry
	  $prog ~/Downloads/Obsidian.AppImage

	  # give it a proper name, an icon and a tooltip
	  $prog -n Obsidian -i ~/pics/obsidian.png -d Notes ~/Downloads/Obsidian.AppImage

	  # show 'Neovim' in the launcher, type 'nvim' in the shell, run in a terminal
	  $prog -n Neovim -c nvim -t /opt/nvim/bin/nvim

	  # file manager drops files on it, and its windows group under its own icon
	  $prog -a %F -w jetbrains-idea -C 'Development;IDE;' /opt/idea/bin/idea

	  # an icon the theme already ships, by name rather than by path
	  $prog -i utilities-terminal -c blah /opt/blah/blah

	  # menu entry only, nothing added to PATH
	  $prog --no-symlink -n 'Some GUI' /opt/thing/thing

	  # on PATH only, no menu clutter
	  $prog --no-desktop -c thing /opt/thing/thing

	  # replace an install that is already there
	  $prog -f -n Obsidian ~/Downloads/Obsidian.AppImage

	  # for every user on the machine
	  sudo $prog -s -n Obsidian /opt/Obsidian.AppImage

	  # take it back out, by the launcher name or the command name
	  $prog -u obsidian

	  # put $prog itself on PATH, so it works from anywhere
	  $prog -b
	EOF
}

# Options, set by parse_args.
name='' cmdname='' icon='' comment='' wmclass='' argspec='' target=''
categories=Utility
terminal=false
sys=0 symlink=1 desktop=1 force=0 remove=0 boot=0 stripext=0

# Install locations, set by resolve_dirs.
bindir='' appdir='' icondir=''

# Derived later: id by derive_names, iconval by install_icon.
id='' iconval=''

# Read the command line into the option globals above.
parse_args() {
	while (($#)); do
		case $1 in
		-n) name=${2-}; shift 2 ;;
		-c) cmdname=${2-}; shift 2 ;;
		-i) icon=${2-}; shift 2 ;;
		-d) comment=${2-}; shift 2 ;;
		-C) categories=${2-}; shift 2 ;;
		-w) wmclass=${2-}; shift 2 ;;
		-a) argspec=${2-}; shift 2 ;;
		-t) terminal=true; shift ;;
		-e|--strip-ext) stripext=1; shift ;;
		-s) sys=1; shift ;;
		-f) force=1; shift ;;
		-u|--uninstall) remove=1; shift ;;
		-b|--bootstrap) boot=1; shift ;;
		--no-symlink) symlink=0; shift ;;
		--no-desktop) desktop=0; shift ;;
		-h|--help) usage; exit 0 ;;
		--) shift; break ;;
		-*) die "no such option: $1" ;;
		*) target=$1; shift ;;
		esac
	done
}

# Pick where things go: system-wide with -s, otherwise under $HOME.
resolve_dirs() {
	if ((sys)); then
		((EUID == 0)) || die "-s needs root"
		bindir=/usr/local/bin
		appdir=/usr/share/applications
		icondir=/usr/share/icons/hicolor
	else
		local data=${XDG_DATA_HOME:-$HOME/.local/share}
		bindir=$HOME/.local/bin
		appdir=$data/applications
		icondir=$data/icons/hicolor
	fi
}

# True when bindir is already on $PATH.
onpath() { case ":$PATH:" in *":$bindir:"*) return 0 ;; esac; return 1; }

# The desktop-entry id for a name: lowercased, anything exotic turned into '-'.
# Both install and uninstall go through this, so they cannot drift apart.
canonical_id() {
	local s=${1,,}
	printf '%s' "${s//[^a-z0-9._-]/-}"
}

# Nudge the desktop caches so the launcher notices what changed.
reload() {
	update-desktop-database "$appdir" 2>/dev/null || true
	gtk-update-icon-cache -qf "$icondir" 2>/dev/null || true
	kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
}

# -b: copy this script into bindir and make sure bindir is on PATH.
bootstrap() {
	local self=$0 dest rc
	[[ -f $self ]] || die "cannot find myself on disk, save the script to a file first"
	self=$(readlink -f -- "$self")
	dest=$bindir/$prog

	if [[ -e $dest ]] && cmp -s -- "$self" "$dest"; then
		say "$dest is current"
	else
		install -Dm755 -- "$self" "$dest"
		say "installed $dest"
	fi

	rc=${ZDOTDIR:-$HOME}/.zshrc
	if onpath; then
		:
	elif [[ -f $rc ]] && grep -qF "$bindir" "$rc"; then
		say "$rc already sets it up, open a new shell"
	else
		# $PATH must stay literal, it expands when the shell starts
		# shellcheck disable=SC2016
		printf '\nexport PATH="$PATH:%s"\n' "$bindir" >> "$rc"
		say "put $bindir on PATH in $rc, open a new shell"
	fi
}

# -u: drop the symlink, the desktop entry and any icons we installed.
uninstall() {
	local want=${target##*/} want_id gone=0 f
	want=${want%.desktop}
	want_id=$(canonical_id "$want")

	# The symlink keeps the command's original casing while the entry and the
	# icons use the id, so match links by id rather than by exact name.
	# That way -u MyTool and -u mytool both clean up everything.
	if [[ -d $bindir ]]; then
		for f in "$bindir"/*; do
			[[ -L $f ]] || continue
			[[ $(canonical_id "${f##*/}") == "$want_id" ]] || continue
			rm -f "$f"; say "rm $f"; gone=1
		done
	fi

	[[ -f $appdir/$want_id.desktop ]] && { rm -f "$appdir/$want_id.desktop"; say "rm $appdir/$want_id.desktop"; gone=1; }
	while IFS= read -r -d '' f; do
		rm -f "$f"; say "rm $f"; gone=1
	done < <(find "$icondir" -type f -name "$want_id.*" -print0 2>/dev/null)

	((gone)) || die "nothing installed as '$want'"
	reload
}

# Check the target is a real file, resolve it, and make sure it can run.
resolve_target() {
	[[ -e $target ]] || die "no such file: $target"
	target=$(readlink -f -- "$target")
	[[ -f $target ]] || die "not a regular file: $target"
	[[ -x $target ]] || { chmod +x "$target"; say "chmod +x $target"; }
}

# Fill in whatever the user did not pass: command name, desktop id, display name.
derive_names() {
	: "${cmdname:=${target##*/}}"
	cmdname=${cmdname%.[Aa]pp[Ii]mage}

	# -e removes the last extension too. This is not the default, because an
	# extension is frequently a part of the name: python3.11, Obsidian-1.5.3.
	if ((stripext)); then
		local base=${cmdname%.*}
		# Keep the name if there is nothing before the dot, e.g. '.hidden'.
		[[ -n $base ]] && cmdname=$base
	fi

	id=$(canonical_id "$cmdname")
	: "${name:=${cmdname^}}"
}

# Symlink the target into bindir so it can be run by name.
link_bin() {
	local link
	mkdir -p "$bindir"
	link=$bindir/$cmdname

	if [[ -L $link && $(readlink -f -- "$link") == "$target" ]]; then
		: # same link already
	elif [[ -e $link || -L $link ]]; then
		((force)) || die "$link exists, -f to replace"
		rm -f "$link"
		ln -s "$target" "$link"
	else
		ln -s "$target" "$link"
	fi

	onpath || say "note: $bindir is not on PATH"
}

# Drop the icon into the right hicolor bucket, and set iconval to whatever
# the desktop entry should reference.
install_icon() {
	[[ -n $icon ]] || return 0

	if [[ ! -f $icon ]]; then
		# assume it names an icon the theme already has
		iconval=$icon
		return 0
	fi

	local ext size w h dst
	ext=${icon##*.}; ext=${ext,,}
	size=$(file -b -- "$icon" | grep -oE '[0-9]+ x [0-9]+' | head -1 || true)
	w=${size%% x *} h=${size##* x }

	if [[ $ext == svg || $ext == svgz ]]; then
		dst=$icondir/scalable/apps/$id.svg
	elif [[ -n $w && $w == "$h" ]]; then
		dst=$icondir/${w}x${h}/apps/$id.$ext
	else
		dst=
	fi

	if [[ -n $dst ]]; then
		mkdir -p "${dst%/*}"
		cp -f -- "$icon" "$dst"
		iconval=$id
	else
		# odd size or format, hicolor has no bucket for it
		iconval=$(readlink -f -- "$icon")
	fi
}

# Write the .desktop file that puts the program in the launcher.
write_desktop() {
	local entry
	mkdir -p "$appdir"
	entry=$appdir/$id.desktop

	if [[ -e $entry ]] && ((!force)); then
		die "$entry exists, -f to replace"
	fi

	{
		echo "[Desktop Entry]"
		echo "Type=Application"
		echo "Version=1.0"
		echo "Name=$name"
		[[ -n $comment ]] && echo "Comment=$comment"
		echo "Exec=$target${argspec:+ $argspec}"
		[[ -n $iconval ]] && echo "Icon=$iconval"
		echo "Terminal=$terminal"
		echo "Categories=$categories"
		[[ -n $wmclass ]] && echo "StartupWMClass=$wmclass"
		echo "StartupNotify=true"
		true
	} > "$entry"

	chmod +x "$entry"
	command -v desktop-file-validate >/dev/null && desktop-file-validate "$entry" || true
}

# Parse, resolve, then run whichever of the three jobs was asked for.
main() {
	parse_args "$@"
	resolve_dirs

	if ((boot)); then
		bootstrap
		exit 0
	fi

	[[ -n $target ]] || { usage; exit 1; }

	if ((remove)); then
		uninstall
		exit 0
	fi

	resolve_target
	derive_names

	if ((symlink)); then
		link_bin
	fi

	install_icon

	if ((desktop)); then
		write_desktop
	fi

	reload
	if ((symlink)); then
		say "$name ready, \`$cmdname\` in the terminal"
	else
		say "$name ready"
	fi
}

main "$@"
