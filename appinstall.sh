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
	usage: $prog [opts] <executable-or-archive>
	       $prog -u <name>
	       $prog -b

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

	archives: .zip (unzip), .tar, .tar.gz/.tgz, .tar.bz2/.tbz2, .tar.xz/.txz (GNU tar)
	config: \${XDG_CONFIG_HOME:-~/.config}/app-install/configfile, install_dir=~/Programs
	--install-dir overrides config; -s defaults to /usr/local/Programs.

	examples:
	  # the usual case, a symlink plus a launcher entry
	  $prog ~/Downloads/Obsidian.AppImage

	  # extract a bundle and select its executable
	  $prog --executable tool/bin/tool -p ~/Programs ~/Downloads/tool.tar.gz

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
install_dir='' archive_executable='' archive_stage=''
archive_destination=''

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
		-p|--install-dir)
			[[ -n ${2-} && $2 != -* ]] || die "$1 needs a directory"
			install_dir=$2; shift 2 ;;
		--executable)
			[[ -n ${2-} && $2 != -* ]] || die "$1 needs a relative path"
			archive_executable=$2; shift 2 ;;
		-s) sys=1; shift ;;
		-f) force=1; shift ;;
		-u|--uninstall) remove=1; shift ;;
		-b|--bootstrap) boot=1; shift ;;
		--no-symlink) symlink=0; shift ;;
		--no-desktop) desktop=0; shift ;;
		-h|--help) usage; exit 0 ;;
		--)
			shift
			(($# == 1)) || die "expected one target after --"
			target=$1; shift ;;
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

# Read values as text. Do not execute commands from the config file.
resolve_install_dir() {
	local config=${XDG_CONFIG_HOME:-$HOME/.config}/app-install/configfile line value
	if [[ -z $install_dir && -e $config ]]; then
		[[ -f $config && -r $config ]] || die "cannot read config: $config"
		while IFS= read -r line || [[ -n $line ]]; do
			line=${line#"${line%%[![:space:]]*}"}
			line=${line%"${line##*[![:space:]]}"}
			[[ -z $line || $line == \#* ]] && continue
			[[ $line =~ ^install_dir[[:space:]]*=(.*)$ ]] || die "invalid config: $line"
			value=${BASH_REMATCH[1]}
			value=${value#"${value%%[![:space:]]*}"}
			value=${value%"${value##*[![:space:]]}"}
			case $value in
			\"*\") value=${value:1:${#value}-2} ;;
			\'*\') value=${value:1:${#value}-2} ;;
			esac
			[[ -n $value ]] || die "install_dir is empty in $config"
			install_dir=$value
		done < "$config"
	fi
	if [[ -z $install_dir ]]; then
		if ((sys)); then install_dir=/usr/local/Programs; else install_dir=$HOME/Programs; fi
	fi
	# Match a literal tilde from the config file.
	# shellcheck disable=SC2088
	case $install_dir in
	'~') install_dir=$HOME ;;
	'~/'*) install_dir=$HOME/${install_dir:2} ;;
	esac
	install_dir=$(realpath -m -- "$install_dir")
}

# Remove incomplete files when extraction fails or the process stops.
cleanup_archive() {
	[[ -n $archive_stage ]] || return 0
	if [[ -d $archive_stage/previous && ! -e $archive_destination ]]; then
		if ! mv -T -- "$archive_stage/previous" "$archive_destination"; then
			say "cannot restore installation; previous files kept in $archive_stage/previous"
			return 1
		fi
	fi
	rm -rf -- "$archive_stage"
}

# Reject paths that can leave the extraction directory.
check_archive_path() {
	local path=$1
	[[ -n $path && $path != /* && /$path/ != */../* ]] ||
		die "unsafe archive path: $path"
	[[ $path != *[[:cntrl:]]* && $path != *\\* ]] ||
		die "unsupported characters in archive path: $path"
}

# Check names and file types before unzip can create any links.
extract_zip() {
	local entry
	command -v unzip >/dev/null || die "ZIP extraction needs unzip"
	unzip -Z -1 "$target" > "$archive_stage/names" || die "cannot list ZIP archive"
	while IFS= read -r entry; do
		check_archive_path "$entry"
	done < "$archive_stage/names"
	unzip -Z -l "$target" > "$archive_stage/types" || die "cannot list ZIP file types"
	while IFS= read -r entry; do
		case $entry in
		Archive:*|'Zip file size:'*|[0-9]*' file'*|[-d]*) ;;
		*) die "unsupported ZIP entry: $entry" ;;
		esac
	done < "$archive_stage/types"
	unzip -q -o "$target" -d "$archive_stage/files" </dev/null || die "cannot extract ZIP archive"
}

# Tar quotes unusual names. Reject these names instead of decoding them.
extract_tar() {
	local mode entry link
	command -v tar >/dev/null || die "tar extraction needs GNU tar"
	tar --list --verbose --numeric-owner --quoting-style=escape --force-local \
		--file="$target" > "$archive_stage/types" || die "cannot list tar archive"
	while read -r mode _ _ _ _ entry; do
		case $mode in
		[-d]*) check_archive_path "$entry" ;;
		l*)
			[[ $entry == *' -> '* ]] || die "invalid tar link: $entry"
			link=${entry#* -> }
			[[ $link != *' -> '* ]] || die "ambiguous tar link: $entry"
			check_archive_path "${entry%% -> *}"
			check_archive_path "$link" ;;
		h*)
			[[ $entry == *' link to '* ]] || die "invalid tar hard link: $entry"
			link=${entry#* link to }
			[[ $link != *' link to '* ]] || die "ambiguous tar hard link: $entry"
			check_archive_path "${entry%% link to *}"
			check_archive_path "$link" ;;
		*) die "unsupported tar entry: $entry" ;;
		esac
	done < "$archive_stage/types"
	tar --extract --file="$target" --directory="$archive_stage/files" --force-local \
		--keep-old-files --no-same-owner --no-same-permissions || die "cannot extract tar archive"
}

# Select an executable without following directory links during the search.
select_archive_executable() {
	local root=$archive_stage/files selected resolved
	local -a candidates=()
	if [[ -n $archive_executable ]]; then
		check_archive_path "$archive_executable"
		selected=$root/$archive_executable
	else
		find "$root" -type f -perm /111 -print0 > "$archive_stage/executables" ||
			die "cannot find executables"
		mapfile -d '' -t candidates < "$archive_stage/executables"
		((${#candidates[@]} == 1)) ||
			die "use --executable PATH; found ${#candidates[@]} executables"
		selected=${candidates[0]}
	fi
	resolved=$(realpath -e -- "$selected") || die "no such executable: $selected"
	[[ $resolved == "$root/"* && -f $resolved ]] ||
		die "--executable must name a file inside the archive"
	chmod u+x -- "$resolved" || die "cannot make executable: $selected"
	printf '%s\n' "${selected#"$root/"}"
}

# Keep tool options and listing formats consistent during validation and extraction.
extract_archive() {
	export LC_ALL=C
	unset TAR_OPTIONS UNZIP UNZIPOPT ZIPINFO ZIPINFOOPT
	case ${target,,} in
	*.zip) extract_zip ;;
	*) extract_tar ;;
	esac
	find "$archive_stage/files" -type f -exec chmod a-s -- {} + ||
		die "cannot clear special permissions"
	select_archive_executable
}

# Check launcher conflicts before moving the extracted files into place.
check_install_conflicts() {
	if ((desktop)) && [[ -e $appdir/$id.desktop || -L $appdir/$id.desktop ]]; then
		((force)) || die "$appdir/$id.desktop exists, -f to replace"
	fi
	if ((symlink)) && [[ -e $bindir/$cmdname || -L $bindir/$cmdname ]]; then
		[[ -L $bindir/$cmdname && $(readlink -f -- "$bindir/$cmdname") == "$target" ]] && return
		((force)) || die "$bindir/$cmdname exists, -f to replace"
	fi
}

# Extract into a separate directory before replacing an existing installation.
install_archive() {
	local base=${target##*/} suffix relative destination
	for suffix in .tar.gz .tar.bz2 .tar.xz .tar .tgz .tbz2 .txz .zip; do
		if [[ ${base,,} == *"$suffix" ]]; then
			base=${base:0:${#base}-${#suffix}}
			break
		fi
	done
	[[ -n $base && $base != . && $base != .. ]] || die "invalid archive name"
	resolve_install_dir
	destination=$install_dir/$base
	archive_destination=$destination
	[[ ! -L $destination ]] || die "archive destination is a symlink: $destination"
	if [[ -e $destination ]]; then
		[[ -d $destination ]] || die "archive destination is not a directory: $destination"
		((force)) || die "$destination exists, -f to replace"
	fi
	mkdir -p -- "$install_dir"
	archive_stage=$(mktemp -d "$install_dir/.app-install-XXXXXXXX")
	trap cleanup_archive EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	mkdir -- "$archive_stage/files"
	relative=$(extract_archive) || die "cannot install archive: $target"
	target=$destination/$relative
	derive_names
	check_install_conflicts
	if [[ -d $destination ]]; then
		mv -T -- "$destination" "$archive_stage/previous"
	fi
	if ! mv -T -- "$archive_stage/files" "$destination"; then
		die "cannot install into $destination"
	fi
	say "extracted $destination"
}

# Check the target is a real file, resolve it, and make sure it can run.
resolve_target() {
	[[ -e $target ]] || die "no such file: $target"
	target=$(readlink -f -- "$target")
	[[ -f $target ]] || die "not a regular file: $target"
	case ${target,,} in
	*.zip|*.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz)
		install_archive; return ;;
	esac
	[[ -z $archive_executable && -z $install_dir ]] || die "archive options need an archive"
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
	[[ -n $cmdname && $cmdname != */* && $cmdname != . && $cmdname != .. ]] ||
		die "invalid command name: $cmdname"

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
	local entry exec_target=$target
	mkdir -p "$appdir"
	entry=$appdir/$id.desktop

	if [[ -e $entry ]] && ((!force)); then
		die "$entry exists, -f to replace"
	fi
	# Quote special characters so paths with spaces remain one argument.
	exec_target=${exec_target//%/%%}
	if [[ $exec_target == *[^a-zA-Z0-9/_.,:+%-]* ]]; then
		exec_target=${exec_target//\\/\\\\\\\\}
		exec_target=${exec_target//\"/\\\\\"}
		exec_target=${exec_target//\$/\\\\\$}
		exec_target=${exec_target//\`/\\\\\`}
		exec_target=\"$exec_target\"
	fi

	{
		echo "[Desktop Entry]"
		echo "Type=Application"
		echo "Version=1.0"
		echo "Name=$name"
		[[ -n $comment ]] && echo "Comment=$comment"
		echo "Exec=$exec_target${argspec:+ $argspec}"
		[[ -n $iconval ]] && echo "Icon=$iconval"
		echo "Terminal=$terminal"
		echo "Categories=$categories"
		[[ -n $wmclass ]] && echo "StartupWMClass=$wmclass"
		echo "StartupNotify=true"
		true
	} > "$entry"

	chmod +x "$entry"
	# Validate when the tool is there, but never fail the install over it.
	if command -v desktop-file-validate >/dev/null; then
		desktop-file-validate "$entry" || true
	fi
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
	[[ -n $archive_stage ]] || derive_names

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
