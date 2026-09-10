# site-checks

Operating guidance for Claude Code sessions in this repo. `README.md` is the
human-facing overview and is not repeated here.

## This repo cannot test itself, and that is not a gap to fix

Both scripts build a Bedrock repo's `Dockerfile`. There is no Bedrock repo
here, and giving a public repo a token that can read the private site repos
would be a worse trade than the one it buys.

So CI here is static analysis plus `tests/resolve-repo-root.sh`. The real
acceptance test is the consuming repo's CI after a lockfile bump.

**Before tagging, verify against `gosuperrad/bedrock-coolify` specifically**,
using the `path` repository in the README. It is the only repo with `base/`,
so it is the only one that exercises the base-building branch of
`decide_base_image`. A site repo would run the whole suite and never touch it.

## Bash 3.2 is a real target

These are normally run from an Apple Silicon laptop before a deploy, and macOS
ships bash 3.2 as `/bin/bash`. CI runners have bash 5, so CI will not catch a
bash 4+ construct. No associative arrays, no `${var^^}`, no `mapfile`, no
`&>>`. `"${arr[@]}"` on an empty array errors under `set -u` in 3.2; index it
with a default instead.

## The e2e script has no `set -e`, deliberately

It collects failures and reports all of them, which is why `fail()` sets a flag
rather than exiting. Two consequences that have already caused bugs:

- A command substitution's `exit` only ends the subshell, so nothing that must
  abort the run may be called that way. `resolve_repo_root` assigns to
  `REPO_ROOT` rather than printing it for exactly this reason.
- An unchecked non-zero exit is silent. Where a command's *success* is what
  makes a later assertion meaningful, check it explicitly and `fail` on it, or
  the assertion passes while proving nothing. The `wp plugin activate` in the
  `DISABLED_PLUGINS` write test is the worked example.

## Do not "simplify" an assertion that looks redundant

Several exist because an earlier version of the suite passed against a broken
implementation:

- the uploads guard tested only a flat path, while every real WordPress upload
  lands in a dated subdirectory, so it passed against a guard that blocked
  nothing reachable
- the same guard was case-sensitive, so `shell.PHP` executed
- the `DISABLED_PLUGINS` check read the option back without exercising the
  write path that was erasing it
- the `log_skip` check asserted an absence without first proving the request
  was served at all

Each has a comment saying so. Read it before deleting the line.

## Do not depend on a site's plugin set

These scripts run against every site built from the starter, and sites remove
starter plugins they have no use for. The `DISABLED_PLUGINS` write test used to
activate `speculation-rules`; when `trinity-takeoffs` removed it, the test
failed with "write path not exercised", which reads exactly like the bug it
guards against. It now writes and activates its own probe plugin. Anything a
check needs to activate, create in the container.

One assumption is left: both `DISABLED_PLUGINS` tests use `cloudflare` as the
entry that must be filtered and then preserved, so a site still has to keep
`cloudflare` installed and listed in `config/environments/local.php`. Lifting
that means reading the site's own list rather than naming a plugin, which is a
larger change than the probe was.

## Adding a check

Add it to the script the check belongs in, never to a second copy elsewhere.
A base-image-only duplicate of the uploads assertions was tried twice in
`bedrock-coolify` and drifted both times, which is the reason this package
exists.
