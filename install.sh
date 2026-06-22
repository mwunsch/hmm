#!/bin/sh

set -u

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'hmm install: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

abs_dir() {
  CDPATH= cd -- "$1" 2>/dev/null && pwd -P
}

quote_dq() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g'
}

find_local_source() {
  script=$0
  case $script in
    */*) ;;
    *) script=$(command -v -- "$script" 2>/dev/null || printf '%s' "$script") ;;
  esac

  script_dir=$(abs_dir "$(dirname -- "$script")" 2>/dev/null || printf '')
  if [ -n "$script_dir" ] && [ -x "$script_dir/bin/hmm" ] && [ -d "$script_dir/libexec" ]; then
    printf '%s\n' "$script_dir"
  fi
}

download_source() {
  work_dir=$1

  tarball_url=${HMM_TARBALL_URL:-}
  if [ -z "$tarball_url" ]; then
    repo=${HMM_REPO:-https://github.com/mwunsch/hmm}
    ref=${HMM_REF:-main}
    tarball_url=${repo%/}/archive/refs/heads/$ref.tar.gz
  fi

  [ -n "$tarball_url" ] || die "no source archive configured"

  need curl
  need tar

  archive=$work_dir/hmm.tar.gz
  mkdir -p "$work_dir" || die "cannot create temp directory"
  curl -fsSL "$tarball_url" -o "$archive" || die "download failed: $tarball_url"
  tar -xzf "$archive" -C "$work_dir" || die "cannot extract source archive"

  src=$(find "$work_dir" -maxdepth 2 -type f -path '*/bin/hmm' -print | sed -n '1p')
  [ -n "$src" ] || die "archive did not contain bin/hmm"
  abs_dir "$(dirname -- "$src")/.."
}

install_source() {
  source_dir=$1
  bin_dir=$2
  libexec_dir=$3

  [ -x "$source_dir/bin/hmm" ] || die "source is missing bin/hmm"
  [ -x "$source_dir/libexec/hmm-codex" ] || die "source is missing libexec/hmm-codex"
  [ -x "$source_dir/libexec/hmm-render" ] || die "source is missing libexec/hmm-render"
  [ -x "$source_dir/libexec/hmm-session" ] || die "source is missing libexec/hmm-session"

  mkdir -p "$bin_dir" "$libexec_dir" || die "cannot create install directories"

  cp "$source_dir/bin/hmm" "$bin_dir/hmm" || die "cannot install hmm"
  cp "$source_dir/libexec/hmm-codex" "$libexec_dir/hmm-codex" || die "cannot install hmm-codex"
  cp "$source_dir/libexec/hmm-render" "$libexec_dir/hmm-render" || die "cannot install hmm-render"
  cp "$source_dir/libexec/hmm-session" "$libexec_dir/hmm-session" || die "cannot install hmm-session"

  chmod 755 "$bin_dir/hmm" "$libexec_dir/hmm-codex" "$libexec_dir/hmm-render" "$libexec_dir/hmm-session" || die "cannot set executable bits"
}

prefix=${HMM_PREFIX:-$HOME/.local}
bin_dir=${HMM_BIN_DIR:-$prefix/bin}

tmp_root=${TMPDIR:-/tmp}/hmm-install.$$
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT HUP INT TERM

source_dir=${HMM_SOURCE_DIR:-}
if [ -z "$source_dir" ]; then
  source_dir=$(find_local_source)
fi
if [ -z "$source_dir" ]; then
  source_dir=$(download_source "$tmp_root")
fi

source_dir=$(abs_dir "$source_dir") || die "cannot resolve source directory"
bin_dir=$(mkdir -p "$bin_dir" && abs_dir "$bin_dir") || die "cannot resolve bin directory"
bin_parent=$(dirname -- "$bin_dir")
libexec_dir=$bin_parent/libexec
libexec_dir=$(mkdir -p "$libexec_dir" && abs_dir "$libexec_dir") || die "cannot resolve libexec directory"

install_source "$source_dir" "$bin_dir" "$libexec_dir"

say "installed hmm to $bin_dir/hmm"
say "installed helpers to $libexec_dir"

case :$PATH: in
  *:"$bin_dir":*) ;;
  *)
    quoted_bin_dir=$(quote_dq "$bin_dir")
    say "add hmm to your PATH:"
    say "  export PATH=\"$quoted_bin_dir:\$PATH\""
    ;;
esac

if command -v codex >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  say "ready: hmm \"how do I list large files?\""
else
  say "note: hmm requires codex and jq at runtime"
fi
