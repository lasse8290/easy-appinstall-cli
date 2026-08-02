#!/usr/bin/env bash
# Tests for appinstall. Every case runs against a throwaway $HOME, so this
# never touches the real one. No root needed, so -s is not covered.
#
#   tests/run.sh          run everything
#   tests/run.sh icon     run only cases whose name matches 'icon'
#   SUT=/path/to/copy tests/run.sh    test some other copy of the script
#
# The harness itself lives in harness.sh.

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

# ---------------------------------------------------------------- static checks
if test_case "script parses"; then
	if bash -n "$SUT" 2>/dev/null; then ok; else bad "bash -n failed"; fi
	teardown
fi

if test_case "shellcheck is clean"; then
	if command -v shellcheck >/dev/null; then
		if shellcheck "$SUT" >/dev/null 2>&1; then ok
		else bad "$(shellcheck -f gcc "$SUT" 2>&1 | head -5)"; fi
	else
		skipped "shellcheck not installed"
	fi
	teardown
fi

if test_case "the tests themselves are shellcheck clean"; then
	if command -v shellcheck >/dev/null; then
		if shellcheck -x "$_harness_dir/run.sh" "$_harness_dir/harness.sh" >/dev/null 2>&1; then ok
		else bad "$(shellcheck -xf gcc "$_harness_dir/run.sh" "$_harness_dir/harness.sh" 2>&1 | head -5)"; fi
	else
		skipped "shellcheck not installed"
	fi
	teardown
fi

# ---------------------------------------------------------------- usage & errors

if test_case "-h prints usage and exits 0"; then
	run -h
	expect_status 0
	expect_out "usage: $progname"
	expect_out "--no-symlink"
	teardown
fi

if test_case "no args prints usage and exits 1"; then
	run
	expect_status 1
	expect_out "usage: $progname"
	teardown
fi

# The file is appinstall.sh but the command must stay appinstall, so the
# extension may never leak into the messages or into what -b installs.
if test_case "the command name drops any .sh extension"; then
	run -h
	expect_status 0
	expect_out "usage: $progname"
	expect_no_out "$progname.sh"
	teardown
fi

if test_case "-h shows worked examples"; then
	run -h
	expect_status 0
	expect_out "examples:"
	expect_out "$progname -b"
	expect_out "--no-symlink"
	teardown
fi

if test_case "unknown option is rejected"; then
	run -Z
	expect_status 1
	expect_out "no such option: -Z"
	teardown
fi

if test_case "missing target is rejected"; then
	run "$sandbox/nope"
	expect_status 1
	expect_out "no such file:"
	teardown
fi

if test_case "directory target is rejected"; then
	run "$sandbox"
	expect_status 1
	expect_out "not a regular file:"
	teardown
fi

# ---------------------------------------------------------------- install

if test_case "full install writes symlink and desktop entry"; then
	run -n "My Tool" -d "does things" -C "Development;IDE;" -w mytool -a %U "$app"
	expect_status 0
	# .AppImage suffix is stripped for the command name, id is lowercased.
	expect_symlink_to "$bin/MyTool" "$app"
	expect_file "$apps/mytool.desktop"
	expect_line "$apps/mytool.desktop" "[Desktop Entry]"
	expect_line "$apps/mytool.desktop" "Type=Application"
	expect_line "$apps/mytool.desktop" "Version=1.0"
	expect_line "$apps/mytool.desktop" "Name=My Tool"
	expect_line "$apps/mytool.desktop" "Comment=does things"
	expect_line "$apps/mytool.desktop" "Exec=$app %U"
	expect_line "$apps/mytool.desktop" "Categories=Development;IDE;"
	expect_line "$apps/mytool.desktop" "StartupWMClass=mytool"
	expect_line "$apps/mytool.desktop" "Terminal=false"
	expect_line "$apps/mytool.desktop" "StartupNotify=true"
	expect_out "in the terminal"
	teardown
fi

if test_case "non-executable target gets chmod +x"; then
	run "$app"
	expect_status 0
	if [[ -x $app ]]; then ok; else bad "target still not executable"; fi
	expect_out "chmod +x"
	teardown
fi

if test_case "desktop entry is executable"; then
	run -c t1 "$app"
	if [[ -x $apps/t1.desktop ]]; then ok; else bad "entry not executable"; fi
	teardown
fi

if test_case "optional fields are omitted when unset"; then
	run -c bare "$app"
	expect_status 0
	expect_no_line_prefix "$apps/bare.desktop" "Comment="
	expect_no_line_prefix "$apps/bare.desktop" "Icon="
	expect_no_line_prefix "$apps/bare.desktop" "StartupWMClass="
	expect_line "$apps/bare.desktop" "Categories=Utility"
	teardown
fi

if test_case "-c overrides the command name"; then
	run -c othername "$app"
	expect_status 0
	expect_symlink_to "$bin/othername" "$app"
	expect_file "$apps/othername.desktop"
	teardown
fi

# Only .AppImage goes by default. Other extensions are often part of the name,
# so they stay until -e asks for them to go.
if test_case "extensions other than .AppImage are kept by default"; then
	tool=$sandbox/thing.sh
	printf '#!/bin/sh\n' > "$tool"
	run "$tool"
	expect_status 0
	expect_symlink_to "$bin/thing.sh" "$tool"
	expect_file "$apps/thing.sh.desktop"
	teardown
fi

if test_case "-e drops the remaining extension"; then
	tool=$sandbox/thing.sh
	printf '#!/bin/sh\n' > "$tool"
	run -e "$tool"
	expect_status 0
	expect_symlink_to "$bin/thing" "$tool"
	expect_file "$apps/thing.desktop"
	teardown
fi

if test_case "-e drops only the last extension"; then
	tool=$sandbox/thing.tar.gz
	printf '#!/bin/sh\n' > "$tool"
	run -e "$tool"
	expect_status 0
	expect_symlink_to "$bin/thing.tar" "$tool"
	teardown
fi

if test_case "-e applies to a name given with -c"; then
	run -e -c other.bin "$app"
	expect_status 0
	expect_symlink_to "$bin/other" "$app"
	expect_file "$apps/other.desktop"
	teardown
fi

if test_case "-e on a name without an extension changes nothing"; then
	run -e -c plain "$app"
	expect_status 0
	expect_symlink_to "$bin/plain" "$app"
	expect_file "$apps/plain.desktop"
	teardown
fi

# '.hidden' is all extension, stripping it would leave an empty name.
if test_case "-e leaves a leading-dot name alone"; then
	tool=$sandbox/.hidden
	printf '#!/bin/sh\n' > "$tool"
	run -e "$tool"
	expect_status 0
	expect_symlink_to "$bin/.hidden" "$tool"
	expect_file "$apps/.hidden.desktop"
	teardown
fi

if test_case "-t sets Terminal=true"; then
	run -c termapp -t "$app"
	expect_line "$apps/termapp.desktop" "Terminal=true"
	teardown
fi

if test_case "id is derived from the command name"; then
	run -c "Weird Name!" "$app"
	expect_status 0
	expect_file "$apps/weird-name-.desktop"
	teardown
fi

# ---------------------------------------------------------------- overwrite

if test_case "re-install without -f fails"; then
	run -c dup "$app"
	expect_status 0
	run -c dup "$app"
	expect_status 1
	expect_out "-f to replace"
	teardown
fi

if test_case "re-install with -f succeeds"; then
	run -c dup "$app"
	run -c dup -f "$app"
	expect_status 0
	expect_out "ready"
	teardown
fi

if test_case "identical existing symlink is left alone"; then
	run -c same --no-desktop "$app"
	expect_status 0
	run -c same --no-desktop "$app"
	expect_status 0
	expect_symlink_to "$bin/same" "$app"
	teardown
fi

if test_case "symlink pointing elsewhere needs -f"; then
	other=$sandbox/Other
	printf '#!/bin/sh\n' > "$other"; chmod 755 "$other"
	run -c clash --no-desktop "$other"
	expect_status 0
	run -c clash --no-desktop "$app"
	expect_status 1
	expect_out "-f to replace"
	teardown
fi

# ---------------------------------------------------------------- half installs

if test_case "--no-desktop installs only the symlink"; then
	run -c binonly --no-desktop "$app"
	expect_status 0
	expect_symlink_to "$bin/binonly" "$app"
	expect_no_file "$apps/binonly.desktop"
	teardown
fi

if test_case "--no-symlink installs only the desktop entry"; then
	run -c deskonly --no-symlink "$app"
	expect_status 0
	expect_no_file "$bin/deskonly"
	expect_file "$apps/deskonly.desktop"
	expect_no_out "in the terminal"
	teardown
fi

# ---------------------------------------------------------------- icons

if test_case "icon: svg goes to scalable"; then
	make_svg "$sandbox/ic.svg"
	run -c svgapp -i "$sandbox/ic.svg" "$app"
	expect_status 0
	expect_file "$icons/scalable/apps/svgapp.svg"
	expect_line "$apps/svgapp.desktop" "Icon=svgapp"
	teardown
fi

if test_case "icon: square png goes to its size bucket"; then
	make_png_square "$sandbox/ic.png"
	run -c pngapp -i "$sandbox/ic.png" "$app"
	expect_status 0
	expect_file "$icons/64x64/apps/pngapp.png"
	expect_line "$apps/pngapp.desktop" "Icon=pngapp"
	teardown
fi

if test_case "icon: theme name is passed through"; then
	run -c themeapp -i firefox "$app"
	expect_status 0
	expect_line "$apps/themeapp.desktop" "Icon=firefox"
	expect_no_file "$icons/scalable/apps/themeapp.svg"
	teardown
fi

if test_case "icon: non-square png falls back to an absolute path"; then
	make_png_wide "$sandbox/wide.png"
	run -c wideapp -i "$sandbox/wide.png" "$app"
	expect_status 0
	expect_line "$apps/wideapp.desktop" "Icon=$sandbox/wide.png"
	expect_no_file "$icons/100x40/apps/wideapp.png"
	teardown
fi

# ---------------------------------------------------------------- uninstall

if test_case "uninstall removes entry, symlink and icon"; then
	make_png_square "$sandbox/ic.png"
	run -c lower -i "$sandbox/ic.png" "$app"
	expect_status 0
	run -u lower
	expect_status 0
	expect_no_file "$apps/lower.desktop"
	expect_no_file "$bin/lower"
	expect_no_file "$icons/64x64/apps/lower.png"
	teardown
fi

if test_case "uninstall accepts a .desktop suffix"; then
	run -c suffixed "$app"
	run -u suffixed.desktop
	expect_status 0
	expect_no_file "$apps/suffixed.desktop"
	teardown
fi

if test_case "uninstall of something absent fails"; then
	run -u ghost
	expect_status 1
	expect_out "nothing installed as 'ghost'"
	teardown
fi

# The symlink is named for the original casing but the entry for the id, so
# uninstall has to match links by id. Both spellings must clean up fully.
if test_case "uninstall by id removes the mixed-case symlink"; then
	run -n "My Tool" "$app"
	expect_status 0
	expect_file "$bin/MyTool"
	expect_file "$apps/mytool.desktop"
	run -u mytool
	expect_status 0
	expect_no_file "$apps/mytool.desktop"
	expect_no_file "$bin/MyTool"
	teardown
fi

if test_case "uninstall by original casing removes both halves"; then
	run -n "My Tool" "$app"
	expect_status 0
	run -u MyTool
	expect_status 0
	expect_no_file "$apps/mytool.desktop"
	expect_no_file "$bin/MyTool"
	teardown
fi

if test_case "uninstall of a spaced name removes the symlink"; then
	run -c "My Tool" "$app"
	expect_status 0
	expect_file "$bin/My Tool"
	expect_file "$apps/my-tool.desktop"
	run -u my-tool
	expect_status 0
	expect_no_file "$bin/My Tool"
	expect_no_file "$apps/my-tool.desktop"
	teardown
fi

if test_case "uninstall leaves unrelated installs alone"; then
	run -c keepme "$app"
	expect_status 0
	run -c dropme "$app"
	expect_status 0
	run -u dropme
	expect_status 0
	expect_no_file "$bin/dropme"
	expect_no_file "$apps/dropme.desktop"
	expect_file "$bin/keepme"
	expect_file "$apps/keepme.desktop"
	teardown
fi

# Only symlinks we made are fair game; a real binary sitting in bindir stays.
if test_case "uninstall never deletes a regular file from bindir"; then
	mkdir -p "$bin"
	printf '#!/bin/sh\n' > "$bin/realbin"
	chmod 755 "$bin/realbin"
	run -u realbin
	expect_status 1
	expect_out "nothing installed as 'realbin'"
	expect_file "$bin/realbin"
	teardown
fi

# ---------------------------------------------------------------- bootstrap

if test_case "-b installs an identical copy and patches the rc"; then
	run -b
	expect_status 0
	expect_out "installed"
	expect_file "$bin/$progname"
	if cmp -s "$SUT" "$bin/$progname"; then ok; else bad "installed copy differs"; fi
	expect_eq "$(stat -c %a "$bin/$progname")" "755"
	# $PATH must land in the rc literally, not pre-expanded.
	# shellcheck disable=SC2016
	expect_line "$HOME/.zshrc" 'export PATH="$PATH:'"$bin"'"'
	teardown
fi

if test_case "-b installs under the bare name, not with .sh"; then
	run -b
	expect_status 0
	expect_file "$bin/$progname"
	expect_no_file "$bin/$progname.sh"
	teardown
fi

if test_case "-b twice is idempotent"; then
	run -b
	expect_status 0
	run -b
	expect_status 0
	expect_out "is current"
	expect_out "already sets it up"
	expect_eq "$(grep -c 'export PATH' "$HOME/.zshrc")" "1"
	teardown
fi

if test_case "-b skips the rc when bindir is already on PATH"; then
	out=$(PATH="$PATH:$bin" "$SUT" -b 2>&1); status=$?
	expect_status 0
	expect_file "$bin/$progname"
	expect_no_file "$HOME/.zshrc"
	teardown
fi

if test_case "-b honours ZDOTDIR"; then
	mkdir -p "$sandbox/zdot"
	out=$(ZDOTDIR=$sandbox/zdot "$SUT" -b 2>&1); status=$?
	expect_status 0
	expect_file "$sandbox/zdot/.zshrc"
	expect_no_file "$HOME/.zshrc"
	teardown
fi

if test_case "-b refreshes a stale copy"; then
	mkdir -p "$bin"
	printf '#!/usr/bin/env bash\n# old\n' > "$bin/$progname"
	chmod 755 "$bin/$progname"
	run -b
	expect_status 0
	expect_out "installed"
	if cmp -s "$SUT" "$bin/$progname"; then ok; else bad "stale copy not refreshed"; fi
	teardown
fi

# ---------------------------------------------------------------- env handling

if test_case "XDG_DATA_HOME is respected"; then
	export XDG_DATA_HOME=$sandbox/xdg
	run -c xdgapp "$app"
	expect_status 0
	expect_file "$sandbox/xdg/applications/xdgapp.desktop"
	expect_no_file "$HOME/.local/share/applications/xdgapp.desktop"
	unset XDG_DATA_HOME
	teardown
fi

if test_case "warns when bindir is not on PATH"; then
	run -c pathapp "$app"
	expect_out "is not on PATH"
	teardown
fi

if test_case "stays quiet about PATH when bindir is on it"; then
	out=$(PATH="$PATH:$bin" "$SUT" -c quietapp "$app" 2>&1); status=$?
	expect_status 0
	expect_no_out "is not on PATH"
	teardown
fi

summary
