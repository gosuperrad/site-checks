#!/usr/bin/env bash
#
# Tests for the repo-root resolution in lib/common.sh.
#
# This is the one piece of logic here whose failure mode is a green suite that
# tested the wrong tree, so it is the one piece with tests of its own. Nothing
# else in the package can be tested without Docker and a real Bedrock repo.
#
# shellcheck disable=SC1090
# $LIB is a variable path by necessity: the point is to source the same file
# the installed scripts source, wherever this checkout happens to live.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/lib/common.sh"

pass=true
ok()   { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; pass=false; }

# Each case runs in its own subshell so a `die` cannot take the harness with
# it, and so REPO_ROOT never leaks between cases.
resolve_in() {
  local dir="$1" arg="${2:-}"
  (
    cd "$dir" || exit 9
    . "$LIB"
    resolve_repo_root "$arg"
    printf '%s\n' "$REPO_ROOT"
  ) 2>&1
}

# A directory that looks like a Bedrock site to assert_bedrock_repo.
make_fake_repo() {
  local d="$1"
  mkdir -p "$d/web"
  : > "$d/Dockerfile"
  : > "$d/composer.json"
  : > "$d/web/index.php"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# macOS puts mktemp under /var, a symlink to /private/var, while git and pwd
# both report the resolved path. Compare against the resolved form.
TMP="$(cd "$TMP" && pwd -P)"

REPO="$TMP/site"
make_fake_repo "$REPO"
mkdir -p "$REPO/web/app/themes/deep"

echo "==> Resolution"

got="$(resolve_in "$REPO")"
[[ "$got" == "$REPO" ]] && ok "repo root resolves to itself" \
  || bad "repo root: expected $REPO, got $got"

# Not a git repo, so this exercises the $PWD fallback rather than git.
got="$(resolve_in "$REPO" "$REPO")"
[[ "$got" == "$REPO" ]] && ok "--repo pointing at the repo" \
  || bad "--repo: expected $REPO, got $got"

# From a subdirectory with no git, $PWD wins and correctly fails the markers.
# This is the case git rev-parse exists to handle, tested next.
got="$(resolve_in "$REPO/web/app/themes/deep")"
[[ "$got" == *"does not look like a Bedrock site repo"* ]] \
  && ok "subdirectory of a non-git tree aborts rather than guessing" \
  || bad "subdirectory: expected an abort, got $got"

if git -C "$REPO" init -q 2>/dev/null; then
  got="$(resolve_in "$REPO/web/app/themes/deep")"
  [[ "$got" == "$REPO" ]] && ok "subdirectory of a git repo resolves to the toplevel" \
    || bad "git toplevel: expected $REPO, got $got"
fi

echo "==> Refusal"

# The case that motivates all of this: a scratch directory that is not a
# Bedrock repo must abort loudly, not resolve to something plausible.
SCRATCH="$TMP/scratch"
mkdir -p "$SCRATCH"
got="$(resolve_in "$SCRATCH")"
[[ "$got" == *"does not look like a Bedrock site repo"* ]] \
  && ok "empty scratch directory aborts" \
  || bad "scratch: expected an abort, got $got"

# A Dockerfile alone is not enough. This is the shape that would have built and
# tested an unrelated project while reporting success.
DOCKERONLY="$TMP/docker-only"
mkdir -p "$DOCKERONLY"
: > "$DOCKERONLY/Dockerfile"
got="$(resolve_in "$DOCKERONLY")"
if [[ "$got" == *"does not look like a Bedrock site repo"* \
   && "$got" == *"composer.json"* && "$got" == *"web/index.php"* ]]; then
  ok "a bare Dockerfile aborts, and the message names what is missing"
else
  bad "docker-only: expected an abort naming the missing markers, got $got"
fi

got="$(resolve_in "$REPO" "$TMP/no-such-directory")"
[[ "$got" == *"is not a directory"* ]] && ok "--repo at a missing path aborts" \
  || bad "--repo missing: expected an abort, got $got"

echo "==> Exit status"

# Non-zero matters as much as the message: CI decides from the status.
( cd "$SCRATCH" && . "$LIB" && resolve_repo_root '' ) >/dev/null 2>&1
[[ $? -ne 0 ]] && ok "a refusal exits non-zero" || bad "a refusal exited 0"

echo "==> Argument parsing"

parsed="$(
  . "$LIB"
  usage() { :; }
  parse_common_args --repo /x mytag 18099
  printf '%s|%s|%s\n' "$REPO_ARG" "$TAG_ARG" "$PORT_ARG"
)"
[[ "$parsed" == "/x|mytag|18099" ]] && ok "--repo with both positionals" \
  || bad "parse: expected /x|mytag|18099, got $parsed"

parsed="$(
  . "$LIB"
  usage() { :; }
  parse_common_args
  printf '%s|%s|%s\n' "$REPO_ARG" "$TAG_ARG" "$PORT_ARG"
)"
[[ "$parsed" == "||" ]] && ok "no arguments leaves every default empty" \
  || bad "parse: expected ||, got $parsed"

parsed="$(
  . "$LIB"
  usage() { :; }
  parse_common_args --repo=/y
  printf '%s\n' "$REPO_ARG"
)"
[[ "$parsed" == "/y" ]] && ok "--repo=<path> form" || bad "parse: expected /y, got $parsed"

parsed="$( . "$LIB"; usage() { :; }; parse_common_args --nope 2>&1 )"
[[ "$parsed" == *"unknown option"* ]] && ok "an unknown option aborts" \
  || bad "parse: expected an abort, got $parsed"

if [[ "$pass" == true ]]; then
  echo "==> All checks passed."
  exit 0
else
  echo "==> One or more checks failed."
  exit 1
fi
