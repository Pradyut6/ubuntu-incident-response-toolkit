# M2 build-runner verification (2026-11-05)

This records **actual checks** performed while preparing the starter files. The build runner is **Debian 13** (not the intended Ubuntu 24.04 guest), and the process ran as root in this isolated build environment. Do not interpret this result as Ubuntu VM certification.

| Check | Actual outcome |
| --- | --- |
| `bash -n bin/uir lib/*.sh tests/smoke.sh` | PASS |
| `bash tests/smoke.sh` | **PASS: 11 / 11** |
| `./bin/uir --help` | PASS |
| `./bin/uir --version` | `uir 0.1.0-dev` |
| `./bin/uir doctor` on build runner | Exit 0; detects Debian 13/root correctly, reports optional tools missing |
| Simulated missing dependencies via restricted `PATH` | PASS; exit 3, missing `jq` reported |
| Hostile command-substitution text | PASS; rejected as data without marker-file creation |
| Preflight invocation with nonexistent HOME | PASS; no persistent HOME state created |
| `shellcheck` | NOT RUN: not installed on build runner |
| `shfmt` | NOT RUN: not installed on build runner |
| `bats tests/unit` | NOT RUN: not installed on build runner |
| Ubuntu 24.04 guest smoke test | NOT RUN: guest is user-managed |
| VM clean-snapshot restore | NOT RUN: guest is user-managed |

**Decision:** M2 passes its portable smoke gate on the build runner; M1 and M2 remain **pending full acceptance on the Ubuntu VM**. Do not mark downstream milestones complete.
