#!/usr/bin/env bash
#
# Shared by both check scripts. Sourced, never executed.
#
# shellcheck disable=SC2034
# Every function here sets variables for the script that sourced it --
# REPO_ROOT, REPO_ARG, TAG_ARG, PORT_ARG, BASE_IMAGE, BUILT_BASE -- which is
# the entire point of the file, so "appears unused" is expected throughout.
#
# Everything here exists to answer one question correctly: which repository
# am I testing? That used to be free, because the scripts lived three levels
# below the repo root and could derive it from their own location:
#
#   REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
#
# Packaging them broke that, and the failure mode is the dangerous kind.
# Copying the old scripts to a scratch directory to run them against another
# repo resolved REPO_ROOT three levels above the scratch directory instead.
# That run failed only because no Dockerfile existed there. Had one existed,
# it would have built and tested an unrelated repo and reported "All checks
# passed". A green suite that tested nothing relevant is worse than no suite,
# so the resolution below is deliberate and the assertions are not optional.

# Set REPO_ROOT in the caller to the repository under test, or fail loudly.
#
# Precedence, most explicit first:
#
#   1. --repo <path>, for the rare case of testing a tree you are not in
#   2. the git toplevel, so running from any subdirectory works
#   3. $PWD, so a tarball or a non-git checkout still works
#
# Whichever wins is then checked against three markers. The markers are the
# actual safeguard: precedence only decides which candidate to try, and any
# candidate can be the wrong tree.
#
# This assigns rather than printing, and that is not a style choice. As
# `REPO_ROOT="$(resolve_repo_root ...)"` the failure path runs inside a
# command substitution, so `die`'s exit would end the subshell and nothing
# else. The e2e script deliberately runs without `set -e`, so it would carry
# on with an empty REPO_ROOT and build whatever `cd ""` left it in -- the
# exact silent-wrong-tree failure these assertions exist to prevent.
resolve_repo_root() {
  local explicit="${1:-}" root

  if [[ -n "$explicit" ]]; then
    [[ -d "$explicit" ]] || die "--repo $explicit is not a directory"
    root="$(cd "$explicit" && pwd)"
  elif root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$root" ]]; then
    :
  else
    root="$PWD"
  fi

  assert_bedrock_repo "$root"
  REPO_ROOT="$root"
}

# A Bedrock site built from this starter, and not merely some directory that
# happens to be there. Three markers rather than one: Dockerfile alone would
# accept any Docker project, and the whole point is that the previous failure
# was a plausible-looking tree with a Dockerfile in it.
assert_bedrock_repo() {
  local root="$1" missing=()

  [[ -f "$root/Dockerfile" ]]      || missing+=('Dockerfile')
  [[ -f "$root/composer.json" ]]   || missing+=('composer.json')
  [[ -f "$root/web/index.php" ]]   || missing+=('web/index.php')

  if (( ${#missing[@]} > 0 )); then
    die "$(printf '%s\n' \
      "$root does not look like a Bedrock site repo." \
      "Missing: ${missing[*]}" \
      "" \
      "These checks build a repo's production Dockerfile and assert against the" \
      "running container, so pointing them at the wrong tree produces a result" \
      "that means nothing. Run from inside the repo, or pass --repo <path>.")"
  fi
}

die() {
  printf '%s\n' "$*" >&2
  exit 2
}

# Parse the arguments both scripts share: [--repo <path>] [tag] [port].
#
# Sets REPO_ARG, TAG_ARG and PORT_ARG in the caller. The positional pair is
# kept because it predates this package and is in both SKILL.md files.
parse_common_args() {
  REPO_ARG=''; TAG_ARG=''; PORT_ARG=''
  local positional=()

  while (( $# > 0 )); do
    case "$1" in
      --repo)   [[ $# -ge 2 ]] || die "--repo needs a path"; REPO_ARG="$2"; shift 2 ;;
      --repo=*) REPO_ARG="${1#--repo=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --)       shift; positional+=("$@"); break ;;
      -*)       die "unknown option: $1 (try --help)" ;;
      *)        positional+=("$1"); shift ;;
    esac
  done

  TAG_ARG="${positional[0]:-}"
  PORT_ARG="${positional[1]:-}"
}

# Which runtime base to build the app image on.
#
# In the starter, base/ IS the base image's source, so build it there and test
# the app against that. Without this, an edit to base/Dockerfile or to the
# Caddy rules it splices would be tested against whatever ghcr already
# publishes and look perfectly fine -- the same silent-pass shape as the
# uploads guard that only ever tested a flat path.
#
# A site repo has no base/, so it tests against the published base its
# Dockerfile pins, which is what that site actually deploys. The base publish
# workflow sets BASE_IMAGE explicitly, having already built a candidate.
#
# Sets BASE_IMAGE and BUILT_BASE in the caller. BUILT_BASE is non-empty only
# when this run built the base itself, which is what the cleanup trap removes.
decide_base_image() {
  local root="$1" tag="$2"

  BUILT_BASE=''
  if [[ -z "${BASE_IMAGE:-}" && -f "$root/base/Dockerfile" ]]; then
    BASE_IMAGE="${tag}-base"
    BUILT_BASE="$BASE_IMAGE"
  fi
}
