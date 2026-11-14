# Testing matrix, evidence and release gates

**Current code status:** v1.0.0 release preparation (not yet published). **Target:** Ubuntu 24.04 LTS. **Executed host:** Ubuntu 24.04 under WSL 2. **Not tested:** native Ubuntu Server or Oracle VirtualBox installation, adversarial multi-user evidence custody, production workloads.

## Automated tests

Run as a **regular user** from the repository root:

```bash
bash tests/run-all.sh 2>&1 | tee "$HOME/uir-final-regression.log"
printf 'Runner exit: %s\n' "${PIPESTATUS[0]}"
```

The 13 runner stages, as observed in the November 14, 2026 WSL acceptance output, comprise:

| Stage | Coverage |
| --- | --- |
| 1 | Bash syntax |
| 2 | ShellCheck warnings (must be installed for a real check) |
| 3 | shfmt four-space formatting (must be installed for a real check) |
| 4 | Portable smoke tests |
| 5 | Bats unit tests (must be installed for a real check) |
| 6 | Store, end-to-end workflow, seeded redaction (28 baseline integration checks) |
| 7 | H01 HTTP probe behavior and failure classification |
| 8 | H02 TCP listening/binding diagnostics |
| 9 | H03 filesystem and inode diagnostics, including WSL `ext2/ext3` label |
| 10 | H04 systemd direct `Requires=` dependencies, including `.slice` and `.target` |
| 11 | H05 bounded process inspection and failure classification |
| 12 | H06 scoped journal metadata and empty/error windows |
| 13 | H07 decoded gzip boundary, structured export privacy and comparison correctness |

**Observed outcome (user-provided WSL terminal output, 2026-11-14):** 13/13 stages reached, overall exit `0`; H07 and the preceding integration stages passed. A grep for `SKIP` returned only the runner's generic reminder line. Before release, examine the *entire* log to confirm ShellCheck/shfmt/Bats truly executed and did not print a tool-specific skip; a zero exit by itself is not proof those optional tools ran.

To detect actual skips:

```bash
grep -nEi '^[[:space:]]*(SKIP|SKIPPED)(:|[[:space:]]|$)|^\[SKIP\]' \
  "$HOME/uir-final-regression.log" || echo 'No explicit test skips found'
```

## Manual acceptance matrix

| Gate | Evidence | Current state |
| --- | --- | --- |
| WSL environment and preflight | `doctor`, service/network utilities | Verified by operator in WSL 2 |
| Twelve exercise scenarios | Private before/after records, notes and screenshots | Reported exercised in WSL 2; mixed isolated live simulations and synthetic fixtures |
| H01 live HTTP probe | INC-013 timeout and local recovery | User-provided snapshots and cleanup screenshots; preserve original private evidence |
| H02 socket checks | Offline/listening/wrong binding | Automated fixtures passed on WSL 2 |
| H03 live filesystem | INC-014 capacity/inode fields | Observed, capture complete |
| H04 live dependency inspection | INC-016, 2/2 active dependencies, collector exit 0 | Observed; overall capture partial due to Nginx permission limit |
| H05 live process inspection | INC-017, 8 process records, collector exit 0 | Observed; process sampler artifact corrected in later code |
| H06 live journal visibility | INC-018, 0 records in 5 min, collector exit 0 | Observed; overall capture partial due to Nginx permission limit |
| H07 archive/privacy regression | Concatenated gzip rejection, redaction and hashes | Automated WSL pass; external manual sharing review still required |
| Native Ubuntu / VirtualBox | Dedicated platform smoke/recovery | **Not performed**; do not claim |
| Clean checkout installation | Temporary Git worktree on native WSL filesystem | **Passed:** all 13 stages, status 0; tracked tree clean |
| Final staged Git diff and secret scan | Staged file listing, whitespace and identifier-pattern checks | **Passed preliminary checks; full history/privacy review remains pending** |
| Documentation consistency, release tag | Synchronized CLI version, links and changelog | **Version preparation in progress; tag and publication pending** |

The operator screenshots do not replace preserved private raw evidence; no real incident archives should be added to Git. See [status tracker](incidents/STATUS.md) for the distinction between live and synthetic exercises.

## Release policy

Publish `v1.0.0` only after the [release checklist](release-checklist.md) is satisfied, the on-machine test log has been reviewed, the `1.0.0` version and test assertions pass a fresh clean-checkout run, and the operator approves the final staged Git diff and history/privacy review. A successful simulation or automated regression does **not** constitute a production SLA, formal penetration test, or native Ubuntu validation.
