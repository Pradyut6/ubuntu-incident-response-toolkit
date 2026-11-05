# Verification matrix and release gates

## Automated tests, without a VM outage

Run from the repository root **as a non-root user**:

```bash
bash tests/run-all.sh
```

The runner performs syntax, available ShellCheck and shfmt checks, portable smoke tests, Bats tests if installed, M3 store regression tests, v1 end-to-end integration, and seeded redaction fixtures. The integration suite creates an isolated `XDG_DATA_HOME` and removes only its temporary test data. It does NOT induce system service failures.

## Host integration gates (Ubuntu 24.04 VM)

| Gate | Evidence to record | Outcome status |
| --- | --- | --- |
| VM boot, console and restore | VirtualBox snapshot `CLEAN-BASELINE`, observed restore | Not yet user-verified |
| Environment preflight | `./bin/uir doctor` on VM | Not yet user-verified |
| Service availability | `systemctl status nginx ssh.socket ssh.service` | Not yet user-verified |
| Core host capture | Host snapshot consistent with `free`, `df`, `ss`, `ip` output | Not yet user-verified |
| Before/after Nginx outage | Nginx failure and recovery as per INC-007 | Not yet user-verified |
| Functional verification | `nginx -t`, `curl`, expected port/listener | Not yet user-verified |
| Export privacy | Inspect all members and verify seeded redaction | Automated fixture pass; VM acceptance pending |
| Incident catalog | Real `before`, `after`, RCA, KB evidence for twelve scenarios | Not yet executed |
| Fresh install | Clean VM checkout and full smoke tests | Not yet user-verified |

## Release criteria

The user decides to publish after the VM tests, case-study results and a final manual privacy audit. This candidate is a feature-complete **implementation draft**, not a claim that the twelve lab demonstrations, ShellCheck/shfmt or production readiness have been verified. Do not turn provisional resume bullets into factual achievements until each result has supporting evidence.
