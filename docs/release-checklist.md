# v1.0.0 publication checklist (H08)

**Release state:** not published. The CLI still reports `1.0.0-rc1`. Complete the following gates **in the existing repository**, on Ubuntu 24.04 / WSL 2, before tagging `v1.0.0` or pushing a public release.

## 1. Confirm the current implementation and test tools

```bash
./bin/uir --version
command -v shellcheck shfmt bats jq python3
bash tests/run-all.sh 2>&1 | tee "$HOME/uir-release-regression.log"
printf 'Runner status: %s\n' "${PIPESTATUS[0]}"
```

Check the *full* log for specific `SKIP` lines, shell warnings and the completed **13 stages**. Historical operator output on 2026-11-14 reported 13/13 with status 0; do not assume a fresh run passes without checking.

## 2. Confirm repository inventory and publication scope

```bash
git status --short
git diff --check
find . -type f \( -name '*.orig' -o -name '*.rej' -o -name '*.pyc' \) -print
```

Include H01–H07 collector files and integration tests. Keep runtime evidence, exports, backups, Python caches, editor files, secrets, downloaded patches, and unreviewed synthetic fixtures **out of the staged commit**. Incident `lab/setup/` scripts may alter services or mounts: review each before publication, never install/run them automatically.

Historical planning and release-candidate notes can remain as explicitly historical records, but ensure the current README/testing guide do **not** present old VM-only plans as accomplished tests.

## 3. Inspect for identifiers and secrets

Use this *review aid*, not as proof that the repository contains no secrets:

```bash
# Avoid printing any matched secret values into shared logs.
rg -l -i '(/mnt/c/Users/|DESKTOP-|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|password[[:space:]]*=)' \
  README.md docs lab config bin lib tests || true
```

Examine any flagged file **privately**. Historical runbooks may legitimately contain placeholder words like "password"; evaluate context. Avoid committing raw private exports, Windows usernames, IPs or SSH keys. Confirm public examples are synthetically generated and approved for sharing. Do not assume structured sanitizer coverage is complete.

## 4. Review the documentation contract

- README feature flags match `./bin/uir --help` and the actual JSON keys.
- Test status says **Ubuntu 24.04 on WSL 2**; no invented VM or production results.
- The incident tracker separates synthetic fixtures, disposable live exercises and private evidence limitations.
- Paths and relative Markdown links resolve after publication; `lab/incidents/` runbook links should be verified against files actually in the repository.
- License, contribution guidance, security contact route and changelog are current.
- Nginx `permission_limited`, `ps` lifetime-average CPU, journal visibility limitations, and redaction caveats are prominently described.

## 5. Stage with review, not a blind commit

```bash
# Recommended: explicitly stage the reviewed source, tests, docs and approved lab scripts.
# Example, NOT a substitute for reviewing newly created files:
git add bin lib tests README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md \
  LICENSE Makefile .gitignore config docs

# Review and stage lab scripts only after you inspect their contents:
# git add lab/setup lab/incidents

git diff --cached --check
git diff --cached --stat
git diff --cached --name-status
git diff --cached
```

**Stop** if any unapproved private file appears in the index. If you need to unstage a file without deleting it, use `git restore --staged -- path/to/file`.

## 6. Version and publish only after approval

When the content and clean-checkout test are accepted, update `UIR_VERSION` in `lib/config.sh` from `1.0.0-rc1` to `1.0.0`, move the Unreleased changelog entry under `[1.0.0]`, and rerun all checks. Record the actual verification date and environment.

Before any public push:

```bash
git remote -v
git status --short
git diff --cached --check
```

Confirm the remote owner/repository, whether it is public, and that no sensitive material exists in the full staged diff **or relevant Git history**. Commit and create the annotated `v1.0.0` tag only after review. Push the chosen branch and tag explicitly; do not force-push or publish automatically from a script.

## 7. Independent release smoke check

Use a clean clone or temporary checkout, with a **new private `XDG_DATA_HOME`**, to verify installation, `doctor`, CLI help, the complete suite, case creation and a read-only capture. Do not carry private incident data into the temporary checkout. Record exact commands, exit codes, hashes and platform details as release evidence.

**Publication decision:** GitHub v1.0.0 is ready only when tests, source review, privacy review, documentation checks, versioning and clean-checkout validation are all explicitly signed off. Otherwise keep the `rc1` label.
