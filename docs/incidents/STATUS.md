# Incident exercise status — WSL 2 training record

**Record basis:** Operator-provided terminal screenshots and follow-up confirmations from **November 6–14, 2026**. The twelve scenarios were exercised on **Ubuntu 24.04 under WSL 2** using purpose-built services, bounded demonstrations or synthetic fixtures. **No Oracle VirtualBox VM or customer production environment was used.**

**Evidence limitation:** The underlying private incident archives have **not** been committed here or independently inspected as a full set. The status below reports what was shown in the user's terminal; it is not a forensic certification. Early milestone documents that say *not run* describe an earlier planning stage and remain historical records.

| ID | Investigation | Basis observed in WSL 2 | Notes |
| --- | --- | --- | --- |
| [INC-001](../kb/KB-001.md) | Custom `ExecStart` fails | Failed→running snapshots, notes, report, hashed handoff, cleanup | Disposable unit |
| [INC-002](../kb/KB-002.md) | Isolated SSH config invalid | Service failure, corrected listener/handshake, archived evidence, cleanup | Dedicated localhost port; not production SSH |
| [INC-003](../kb/KB-003.md) | Nginx file permission denied | Private content permissions and HTTP recovery check, report and cleanup | Service remained running; HTTP check verified separately |
| [INC-004](../kb/KB-004.md) | APT lock contention message | Read-only host checks and snapshot/report; synthetic lock fixture | **No actual dpkg lock induced** |
| [INC-005](../kb/KB-005.md) | Bounded CPU utilization | Controlled workload, before/after host measurements, archived evidence | Load average is not instantaneous CPU or proof of recovery |
| [INC-006](../kb/KB-006.md) | Capped tmpfs becomes full | Isolated 16 MiB mount, ENOSPC, before/after capture, checksum and unmount | Main root filesystem not filled |
| [INC-007](../kb/KB-007.md) | Invalid isolated Nginx config | Failed service, corrected config, active state and cleanup | Service fixture, not primary Nginx configuration |
| [INC-008](../kb/KB-008.md) | Nginx proxy backend unavailable | Upstream timeout, backend recovery, HTTP check, hash and cleanup | Distinguishes proxy process from backend health |
| [INC-009](../kb/KB-009.md) | DNS timeout | Isolated query timeout, before/after records, export and cleanup | Main WSL resolver unchanged |
| [INC-010](../kb/KB-010.md) | Local network reachability | Loopback address-specific connectivity failure/recovery, before/after, hash and cleanup | Synthetic firewall evidence; no main WSL firewall change established |
| [INC-011](../kb/KB-011.md) | Missing app stdout/stderr from journal | Disposable service with discarded streams, fixed journal settings, capture/archive and cleanup | Service status alone was not the symptom |
| [INC-012](../kb/KB-012.md) | Required dependency startup failure | Inactive→active service comparison; report, 10-file checksum validation, unit cleanup | Both dependent and prerequisite units removed |

**Separate hardening acceptance (H01–H07):** Regression stages **13/13**, exit `0` observed on WSL 2 on **2026-11-14**. Follow-on live collector validations were recorded under `INC-013`–`INC-018`; those are engineering tests, **not** a new set of production incidents. Nginx-based H04/H06 captures may remain `partial` because unprivileged `nginx -t` is permission-limited, despite the opt-in collector returning success.

## What remains before public release

- Convert only **reviewed, synthetic** material into public case-study excerpts (using [template](TEMPLATE.md)); do not copy private snapshots/handoffs into Git.
- Recheck redaction of every proposed example and archive independently; checksum success does not imply anonymity.
- Complete clean-checkout regression, documentation link checks, staged-diff review and version/tag approval per [release checklist](../release-checklist.md).
- If native Ubuntu Server acceptance is later performed, record it as a **separate** result, not a retroactive claim about these WSL 2 exercises.

Reference knowledge-base pages remain **training drafts**. Their illustrative VM commands are not necessarily the exact commands used in the WSL 2 exercises.
