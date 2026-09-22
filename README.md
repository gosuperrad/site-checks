# site-checks

The smoke and end-to-end checks for a Super Rad WordPress/Bedrock site image,
as **one shared definition** rather than a copy in every site repo.

```bash
composer require --dev superrad/site-checks
vendor/bin/docker-smoke-test
vendor/bin/docker-e2e-test
```

Both build the repo's production `Dockerfile` and assert against the running
container. Neither needs credentials, a live deploy, or anything outside
Docker.

## Why this is a package

These two scripts used to live in `.claude/skills/` in every repo built from
[bedrock-coolify](https://github.com/gosuperrad/bedrock-coolify). Three copies
disagreed. One site's e2e script was missing the regression test for a bug
that had erased 9 rows from that site's own database, and the same script was
missing the assertion that would have caught a stale `development.php` on a
different site.

A drifted test is worse than drifted implementation, because its failure mode
is **passing**.

A Composer package fixes it for both consumers at once, which a reusable
GitHub workflow would not: CI and a human at a laptop both run
`vendor/bin/...`, so they are running byte-identical code by construction, and
`composer.lock` says which version.

## The two checks

**`docker-smoke-test`** runs the image against a deliberately unreachable
database. It covers `/healthz.php` reporting DB-unreachable, the homepage
rendering WordPress's own error page instead of crashing the container, the
uploads-PHP guard at every path shape a real upload can take (nested, `.phtml`,
path-info, uppercase `.PHP`), both `xmlrpc` cases, the access log and its
`log_skip` matcher from both sides, WP-CLI, the `bin/` deploy scripts, and
the production `php.ini`.

**`docker-e2e-test`** stands the image up against a real MariaDB container and
installs WordPress, so it can reach what the smoke test cannot: WebP output,
the Super Rad login stylesheet actually loading,
the `DISABLED_PLUGINS` filter on both its read and write paths, WP cron, and
`wp db export`.

Several assertions look redundant and are not. Each one that reads that way is
there because an earlier version of the suite passed against a broken
implementation. The comments say which; read them before deleting one.

## Which runtime base gets tested

Both scripts build `base/Dockerfile` when the repo has one, and otherwise test
the published base that repo's `Dockerfile` pins.

That conditional is deliberate. Only the starter has `base/`, and there an edit
to the Caddy hardening rules must be tested against the edit rather than
against whatever `ghcr.io/gosuperrad/bedrock-base:1` already publishes. A site
repo has no `base/` and correctly tests the image it actually deploys.

Override with `BASE_IMAGE=<image>`, which is how the base publish workflow
points both suites at a candidate it has already built.

## Vendor Composer credentials

A site that requires ACF Pro or Gravity Forms from their vendors' Composer
repositories needs credentials in the image build's `composer install`
(gosuperrad/bedrock-coolify#7). Both scripts hand them to `docker build` as a
BuildKit secret with id `COMPOSER_AUTH`, which the site's `Dockerfile` mounts
for that one step. A secret, not a build arg: a build arg is written into the
image history, where anyone who can pull the image can read the licence key.

They are found in this order, and only the source is printed:

1. `$COMPOSER_AUTH`, the JSON Composer itself reads. CI sets it from the org
   secret.
2. `auth.json` in the repository under test.
3. `~/.ddev/homeadditions/.composer/auth.json`, which also serves
   `ddev composer` in every project on the machine, so a laptop keeps one copy.

With none of them, the build runs without credentials. That is fine for a site
with no vendor packages; any other fails in `composer install` with Composer's
own 401 naming the host.

## Which repository gets tested

In precedence order: `--repo <path>`, then the git toplevel, then `$PWD`.

Whichever wins must contain `Dockerfile`, `composer.json` and `web/index.php`,
or the run aborts. Both scripts also print the resolved path before they build
anything.

That is not defensive padding. The scripts previously derived the repo from
their own location, three levels up:

```bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
```

Copying them to a scratch directory to run against another repo resolved three
levels above the scratch directory instead. That run failed only because no
`Dockerfile` happened to be there. Had one been, it would have built and tested
an unrelated repo and printed `All checks passed`.

## Changing a check

The scripts have no repo of their own to test against, so verify against a real
site repo before tagging. Point that repo at a local checkout with a `path`
repository:

```json
"repositories": [
  { "type": "path", "url": "../site-checks", "options": { "symlink": true } }
]
```

Then `composer update superrad/site-checks` there and run both suites. With
`symlink: true`, edits here are live in `vendor/bin` with no reinstall.

Verify against **bedrock-coolify** specifically: it is the only repo with
`base/`, so it is the only one that exercises the base-building half.

Then tag, and bump the lockfile in each site.

## Requirements

Bash, Docker and `curl`. Bash 3.2 is a supported target, because these are
normally run from an Apple Silicon laptop before a deploy and macOS still ships
3.2 as `/bin/bash`. That is also why the base image is published multi-arch.

Install with `--require-dev`. The production image builds with
`composer install --no-dev`; test tooling must not land in it.
