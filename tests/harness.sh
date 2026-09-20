# shellcheck shell=bash
# This file is sourced, so the vars and helpers below look unused from here.
# shellcheck disable=SC2034
#
# Tiny test harness. Source this, write cases, then call summary.
# Assumes the caller has done `set -uo pipefail` -- deliberately not `-e`, so
# one failing assertion does not abandon the rest of the run.
#
#   test_case <name>    open a case; returns 1 when the name filter excludes it
#   run <args...>       run the script under test, capturing $out and $status
#   expect_* ...        assertions, each counting one pass or one fail
#   teardown            close a case and delete its sandbox
#   summary             print totals and exit 0/1
#
# Inside a case these point into a fresh sandbox:
#   $sandbox  the temp dir, and $HOME lives under it
#   $bin $apps $icons   where the script should install things
#   $app      a non-executable MyTool.AppImage to install
#   $out $status        results of the last run

_harness_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

SUT=${SUT:-$_harness_dir/../appinstall.sh}
[[ -f $SUT ]] || { echo "no such script: $SUT" >&2; exit 1; }
SUT=$(readlink -f -- "$SUT")

# The script calls itself by its basename minus any .sh, so the file may be
# appinstall.sh while the command stays appinstall. No test may hardcode it.
progname=${SUT##*/}
progname=${progname%.sh}

# First positional arg of the calling script, if any, filters cases by name.
filter=${1-}

pass=0 fail=0 skip=0
current=''
failed_names=()

# ---------------------------------------------------------------- sandbox

# Fresh sandbox per case, so nothing ever touches the real $HOME.
setup() {
	sandbox=$(mktemp -d) || exit 1
	export HOME=$sandbox/home
	mkdir -p "$HOME"
	unset XDG_DATA_HOME XDG_CONFIG_HOME ZDOTDIR
	bin=$HOME/.local/bin
	apps=$HOME/.local/share/applications
	icons=$HOME/.local/share/icons/hicolor
	# Left non-executable on purpose, so the chmod +x path gets exercised.
	app=$sandbox/MyTool.AppImage
	printf '#!/bin/sh\necho hi\n' > "$app"
	chmod 644 "$app"
}

# Guarded on /tmp so a surprising $sandbox can never take out something real.
teardown() { [[ -n ${sandbox-} && $sandbox == /tmp/* ]] && rm -rf "$sandbox"; }

# ---------------------------------------------------------------- fixtures

# Embedded so CI needs no image tooling, and so `file` reports a real size for
# the icon-bucket logic. 64x64 red, and 100x40 green. Minimal uncompressed-ish
# RGB PNGs, hand-built rather than pulled in as binary fixtures.
# Generate these values with: python3 tests/make_pngs.py
#
# Colour bit depth 8, colour type 2 (truecolour), no interlace; each scanline
# is prefixed with filter byte 0. zlib level 9 matters, the base64 below only
# matches at that level.
_PNG_SQUARE=iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAS0lEQVR42u3PQQkAAAgAsetfWiP4FgYrsKZeS0BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEDgsqnc8OJg6Ln3AAAAAElFTkSuQmCC
_PNG_WIDE=iVBORw0KGgoAAAANSUhEUgAAAGQAAAAoCAIAAACHGsgUAAAASklEQVR42u3QMQ0AAAjAsPk3DRb4eJpUQWviSoEsWbJkyUKBLFmyZMlCgSxZsmTJQoEsWbJkyUKBLFmyZMlCgSxZsmTJQoEsWd8Ws7SRQvvMlnYAAAAASUVORK5CYII=

# Square icon, lands in a hicolor size bucket.
make_png_square() { printf '%s' "$_PNG_SQUARE" | base64 -d > "$1"; }
# Non-square icon, has no hicolor bucket to go in.
make_png_wide()   { printf '%s' "$_PNG_WIDE" | base64 -d > "$1"; }
# Scalable icon.
make_svg() { printf '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"/>\n' > "$1"; }

# Build real archives with a program and a data file.
make_archive() {
	archive=$sandbox/Bundle.$1
	python3 "$_harness_dir/make_archive.py" "$archive" "$1" "${2:-normal}"
}

# ---------------------------------------------------------------- running

# run <args...> -- always returns 0, the exit code lands in $status instead.
run() {
	out=$("$SUT" "$@" 2>&1)
	status=$?
	return 0
}

# Open a case. Returns non-zero when filtered out, so callers guard with `if`.
test_case() {
	current=$1
	if [[ -n $filter && $current != *"$filter"* ]]; then
		return 1
	fi
	setup
	return 0
}

# ---------------------------------------------------------------- tallying

# Count one satisfied assertion.
ok() { pass=$((pass + 1)); }

# Count one failure and report it, with the last run's output for context.
bad() {
	fail=$((fail + 1))
	failed_names+=("$current")
	printf 'FAIL %s\n     %s\n' "$current" "$1" >&2
	[[ -n ${out-} ]] && printf '     output: %s\n' "${out//$'\n'/ | }" >&2
	return 0
}

# Note a case we could not run, e.g. a missing optional tool.
skipped() { skip=$((skip + 1)); printf 'SKIP %s (%s)\n' "$current" "$1"; }

# ---------------------------------------------------------------- assertions

# The script under test exited with this code.
expect_status() {
	if [[ $status -eq $1 ]]; then ok; else bad "expected exit $1, got $status"; fi
}
# Output contains this substring.
expect_out() {
	if [[ $out == *"$1"* ]]; then ok; else bad "output missing '$1'"; fi
}
# Output does not contain this substring.
expect_no_out() {
	if [[ $out != *"$1"* ]]; then ok; else bad "output should not contain '$1'"; fi
}
# Path exists and is a file, following symlinks.
expect_file() {
	if [[ -f $1 ]]; then ok; else bad "missing file: $1"; fi
}
# Path does not exist at all, symlink or otherwise.
expect_no_file() {
	if [[ ! -e $1 ]]; then ok; else bad "should not exist: $1"; fi
}
# expect_symlink_to <link> <resolved target>
expect_symlink_to() {
	local got
	if [[ ! -L $1 ]]; then bad "not a symlink: $1"; return; fi
	got=$(readlink -f -- "$1")
	if [[ $got == "$2" ]]; then ok; else bad "$1 -> $got, wanted $2"; fi
}
# expect_line <file> <exact whole line>
expect_line() {
	if grep -qxF -- "$2" "$1" 2>/dev/null; then ok; else bad "$1 has no line '$2'"; fi
}
# expect_no_line_prefix <file> <prefix that must not start any line>
expect_no_line_prefix() {
	if grep -q "^$2" "$1" 2>/dev/null; then bad "$1 should have no '$2' line"; else ok; fi
}
# expect_eq <actual> <wanted>
expect_eq() {
	if [[ $1 == "$2" ]]; then ok; else bad "got '$1', wanted '$2'"; fi
}

# ---------------------------------------------------------------- summary

# Print the tally and exit: 0 all good, 1 if anything failed. A filter that
# matched nothing is a failure too, otherwise a typo looks like a green run.
summary() {
	if ((pass + fail + skip == 0)); then
		if [[ -n $filter ]]; then
			printf 'no tests matched: %s\n' "$filter" >&2
		else
			printf 'no tests ran\n' >&2
		fi
		exit 1
	fi

	printf '\n%d passed' "$pass"
	((skip)) && printf ', %d skipped' "$skip"
	((fail)) && printf ', %d FAILED' "$fail"
	printf '\n'

	if ((fail)); then
		printf 'failing tests:\n'
		printf '  %s\n' "${failed_names[@]}"
		exit 1
	fi
	exit 0
}
