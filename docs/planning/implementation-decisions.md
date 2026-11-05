# Implementation decisions (v1.0.0 release candidate)

The original [blueprint](blueprint-v1.md) is a preserved design artifact, not a current implementation status document. The current CLI, README and tests supersede its proposed code snippets when they differ.

| Decision | Implementation | Reason / compromise |
| --- | --- | --- |
| Single development folder | `ubuntu-incident-response-toolkit/`, packaged only once after completing v1 | Avoid repetitive ZIP downloads and extracted version directories |
| Primary test target | Ubuntu 24.04 VM; WSL only for read-only development | Fault injection must not damage the user’s daily development environment |
| CLI name | `uir` | Short and easy to type; not a guarantee of global command uniqueness |
| Runtime data | XDG data root, private directories and files | Keeps evidence out of Git and avoids shared Windows drive semantics |
| Service scope | `host`, Nginx, SSH/socket, and `uir-*` disposable units | Intentionally constrained; does not execute arbitrary service-specific diagnostic commands |
| Evidence | JSON snapshot + gzip diagnostics / JSONL journal | Portable, inspectable, compressible |
| Retention | 30 days, 500 MiB, 10 MiB capture, manual-only prune | Prevents silent deletion; no automatic retention task |
| Redaction | Local and public-stage regexes; explicit manual review | Best effort only; never a guarantee of anonymity |
| Case notes | Human-written `note` types + status | Prevents fabrication of RCA from a simple diff |
| Lab catalog | Twelve scenario runbooks and KB **drafts** | Exercise results only documented after independent VM verification |
| Monitoring | Deferred v1.1 | Event-triggered privilege/rate-limit design needs a separate threat review |
| GUI | Deferred v2 | Must not weaken the validated CLI/data boundary |
| Repository publication | No GitHub push before VM acceptance and privacy audit | Meets the user’s release workflow |
