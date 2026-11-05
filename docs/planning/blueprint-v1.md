# Ubuntu Server Incident Response & Automated Troubleshooting Toolkit

**Engineering blueprint · Draft v1.0 · For review before implementation**

> **Domain:** Linux System Administration · Ubuntu Technical Support · Incident Response · Bash Automation  
> **Primary audience:** Canonical Linux/Cloud/Technical Support recruiters and engineers  
> **Target environment:** Ubuntu Server 24.04 LTS in an isolated local virtual machine  
> **Implementation order:** Secure, tested Bash command-line tool → incident lab and documentation → polished GitHub publication → optional graphical dashboard  
> **Status:** **DESIGN ONLY — not approved for implementation**

---

## 1. Project vision

Build a reproducible **Ubuntu incident-response workbench** and a **real Bash-based diagnostic command-line application** that helps a support engineer investigate service outages and Linux host problems, collect and preserve evidence, compare diagnostics before and after corrective action, and prepare sanitized, compressed incident handoff bundles.

This is **not** a terminal demo that prints a few commands. The deliverable must behave as an actual tool: predictable interface; persistent incidents; safe, bounded collection; searchable evidence; configurable retention; useful errors; tests; technical documentation; and a reproducible Ubuntu lab with defensible incident analyses.

### 1.1 Outcome we want

A reviewer should be able to clone the eventual GitHub repository, follow the README, install prerequisites, run the CLI on a compatible Ubuntu machine, create an incident, collect a diagnostic snapshot, search it, compare it with a post-remediation snapshot, export a sanitized archive, and understand exactly what the tool can and cannot do. The repository should demonstrate how its author reasons through technical support cases—not just how they run shell commands.

### 1.2 Principles that guide every decision

1. **Real support workflow:** intake → triage → evidence → hypothesis → safe fix → verification → customer-ready handoff → knowledge-base article.
2. **Secure by default:** least privilege; explicit collection scope; private local storage; redaction; safe retention; no unrestricted automatic remediation.
3. **Small verified increments:** implement one capability; add tests; run them; record results; accept the milestone; only then continue.
4. **Reproducible and transparent:** failures deliberately created *only inside the isolated lab*; documented setup and recovery steps; outputs traceable to captured data.
5. **Clear ownership:** descriptive commits, real troubleshooting notes, documented engineering trade-offs, realistic limitations, and defensible claims.
6. **Portfolio authenticity:** never misrepresent simulated incidents as real customer/production incidents or fabricate performance outcomes.

---

## 2. Career alignment and STAR story

The known Canonical support-oriented job context emphasizes Linux troubleshooting, case ownership, customer communication, timely prioritization, knowledge-base maintenance, and understanding how support teams interact with engineering. Recent Canonical support job descriptions also emphasize diagnosing logs and complex Linux/cloud problems. This project will produce visible artifacts for these competencies, but **a portfolio project does not substitute for production support experience**.

| Canonical-relevant competency | Observable evidence in this repository |
| --- | --- |
| Ubuntu/Linux systems knowledge | Ubuntu 24.04 service, process, storage, permissions, package and networking incidents |
| Technical triage and RCA | Repeatable incident records with symptom, hypotheses, evidence, cause, and verified resolution |
| Bash automation | Tested collectors and CLI commands with input validation, exit codes and error handling |
| Customer case ownership | Severity, timestamps, status changes, handoff notes, updates and follow-up actions |
| Documentation and knowledge sharing | 10–12 troubleshooting case studies, KB articles, installation docs and runbooks |
| Risk awareness | Lab isolation, read-only diagnosis by default, least privilege, redaction, bounded storage |
| Software quality | Unit/integration tests, ShellCheck, formatting, acceptance checklists, failure-mode tests |

### 2.1 The eventual STAR framing

- **Situation:** Ubuntu service failures and resource problems can be difficult to diagnose consistently when relevant logs and system details are scattered.
- **Task:** Design a reproducible lab and a technician-friendly diagnostic tool that captures, retains, finds, compares, and safely exports incident evidence.
- **Action:** Build a modular Bash CLI, reproduce a dozen controlled Ubuntu incidents, collect before/after snapshots, write tests, and document the analysis and resolution paths.
- **Result:** Report only **measured, reproducible** outcomes, such as number of incident classes covered, tests passed, median data-collection duration, archive size versus source size, and percentage of intentionally seeded sensitive strings removed from export fixtures. Measure these *after implementation*; do not insert invented percentages into the README or CV.

### 2.2 Scope boundaries

**In v1.0:** One Ubuntu host at a time; locally initiated investigation; known service names; capture, retention, search, compare, sanitized export; 10–12 lab incidents; CLI tests; docs.

**Not in v1.0:** Multi-host remote orchestration, arbitrary shell-command execution, full monitoring platform, automatic service repair, enterprise SIEM integration, password collection, cloud deployment, web authentication, or a graphical application.

**Possible v1.1:** Read-only systemd-triggered collection when an allowlisted service fails. This is opt-in, rate-limited, and developed only after stable v1.0.

**Future v2.0:** A graphical dashboard backed by the same evidence format and an explicitly designed local API/data-access layer. Do not bolt on a GUI before the CLI/data model are stable.

---

## 3. Reference setup and platform assumptions

| Item | Proposed choice | Reason / caveat |
| --- | --- | --- |
| Guest OS | Ubuntu Server **24.04 LTS** | Direct alignment with Ubuntu support workflows |
| Hypervisor | **Oracle VirtualBox** on the existing host | Local, repeatable isolated lab; alternative hypervisor only if VirtualBox causes compatibility problems |
| Starter VM | **2 virtual CPUs, 2 GB RAM, ~25 GB dynamically allocated virtual disk** | Conservative baseline for an 8 GB host; adjust after observing actual resource pressure |
| VM networking | NAT first; host-only adapter only if needed for developer access | Do not expose intentionally broken services to the public internet |
| Access | Guest console plus SSH from the host, if enabled | Always maintain console access before experimenting with SSH/firewall settings |
| Editor | VS Code or normal terminal editor | Developer's choice; code runs and is tested inside Ubuntu |
| Main language | Bash on Ubuntu | CLI and core collectors are Bash; `jq` can assist with safe JSON generation and queries |
| Core dependencies | `bash`, `systemctl`, `journalctl`, `iproute2`, `coreutils`, `gzip`, `tar`, `jq`, and scenario-specific tools | Detect missing prerequisites; optional commands fail gracefully |
| Quality tools | `shellcheck`, `shfmt`, `bats-core` | Static checks, repeatable style, automated Bash tests |
| Service targets | Nginx, OpenSSH, selected systemd units | Dedicated training services/fixtures where possible |

**Ubuntu 24.04-specific note:** OpenSSH typically uses systemd socket activation. SSH test plans must consider `ssh.socket` as well as `ssh.service`, and must verify effective configuration rather than assuming all installations behave identically.

**Lab safety:** Take a clean VM snapshot after initial setup. Keep the console accessible. Fault-injection procedures belong under `lab/`, must carry a warning, and must include cleanup/recovery steps. Never run them against a work, school, customer, or production machine.

### 3.1 Preflight checklist

- [ ] Confirm Ubuntu version, available RAM, free disk, network mode and hypervisor virtualization support.
- [ ] Confirm the host has enough capacity to reserve the VM resources without becoming unstable.
- [ ] Install guest updates and tools, record their versions, and take the **CLEAN-BASELINE** snapshot.
- [ ] Prove guest console, shell access, DNS resolution, package manager and Nginx test page function before introducing faults.
- [ ] Record the VM restore process and verify it once.

---

## 4. User workflows and functional requirements

The name `uir` below is a **proposed CLI command**, not a command that already exists. The command names and flags are subject to review before implementation.

### 4.1 Basic operator journey

1. Run `uir doctor` to inspect prerequisites and permissions.
2. Create a tracked incident with ID, service, severity and summary.
3. Run a **before** snapshot: CPU/memory/disk/network/service state plus a time-bounded relevant journal/log excerpt.
4. Investigate with standard Ubuntu utilities and write the hypothesis and corrective action.
5. Apply the repair **manually** in the lab; the toolkit does not perform arbitrary repair actions.
6. Run an **after** snapshot and compare the two phases.
7. Produce a concise report, sanitize export contents, preview what will be included, and generate a portable `.tar.gz` handoff.
8. Search old incidents; set or modify retention; run a dry-run cleanup when needed.

### 4.2 Proposed command interface (examples, not implemented)

```bash
uir --help
uir doctor
uir init
uir incident create --id INC-007 --service nginx --severity high
uir capture --incident INC-007 --phase before --service nginx
uir capture --incident INC-007 --phase after --service nginx
uir incident list
uir incident show INC-007
uir incident search --service nginx --since 2026-11-01
uir incident search --text 'address already in use'
uir compare --incident INC-007
uir export --incident INC-007 --output ./INC-007-handoff.tar.gz
uir retention status
uir retention set --days 30 --max-storage-mb 500
uir retention prune --dry-run
uir retention prune --yes
```

The tool should provide `--help`, `--version`, helpful error messages, nonzero exit codes for failures, machine-readable structured evidence, and a clear distinction between **data collection**, **operator notes**, and **inferences**.

### 4.3 Requirements and acceptance criteria

| ID | Requirement | Must be verifiable by |
| --- | --- | --- |
| F-01 | Ubuntu dependency/privilege preflight | Missing command or inadequate journal permissions are reported without crashing |
| F-02 | Create/list/show incidents | Incident metadata persists across separate CLI invocations |
| F-03 | Gather host health | CPU/load, memory, storage, network context, uptime and OS version recorded with timestamps |
| F-04 | Gather service diagnostics | Service unit state, recent journal, effective relevant configuration test and listening ports when available |
| F-05 | Targeted capture scope | Operator selects service, phase and capture period; broad unrestricted dump is not the default |
| F-06 | Before/after comparisons | Diff summary identifies concrete service/port/resource changes; preserves source snapshots |
| F-07 | Search | Filter by incident ID, date/time, service, severity and error text without executing searched text |
| F-08 | Retain evidence | User chooses a retention period and storage cap; saved records survive CLI exit and guest reboot |
| F-09 | Compressed local storage | High-volume diagnostic text stored compressed; size and readable recovery tested |
| F-10 | Export/handoff | Generate sanitized `.tar.gz` including metadata, evidence, report and manifest |
| F-11 | Security defaults | Private filesystem permissions; validated IDs/paths; no command injection; no silent privilege escalation |
| F-12 | Incident documentation | 10–12 reproducible cases with symptoms, diagnostics, RCA, fix, verification and KB article |
| F-13 | Non-destructive defaults | The core CLI reads and reports; deletion requires explicit opt-in and dry-run support |
| F-14 | Reliability | CLI and storage operations handle missing logs, unavailable services, timeouts and low disk safely |
| F-15 | Optional failure-triggered capture | Demonstrated only in v1.1 with explicit enable/disable, allowlist and rate limits |

---

## 5. High-level architecture

```text
                 Operator / Ubuntu support technician
                               |
                          `uir` Bash CLI
                               |
                  +------------+------------+
                  |                         |
            Input validation          Incident lifecycle
            configuration             metadata and notes
                  |                         |
                  +------------+------------+
                               |
                    Read-only collectors
          (host health / systemd / journal / ports)
                               |
                 Size/time-bounded capture
                               |
                   Sanitization pipeline
                               |
                  Private incident store
                   |       |         |
                 Search  Compare   Retention
                   |       |         |
                   +-------+---------+
                               |
                   Export staging & review
                               |
               `.tar.gz` + SHA-256 manifest
```

**Important trust boundary:** System logs are untrusted inputs. Never `eval`, `source`, or execute anything parsed from a log entry, search string, service name or incident record. Run fixed, allowlisted diagnostics with securely quoted parameters. Never blindly archive `/var/log` or all of `/etc`.

### 5.1 Proposed repository layout

```text
ubuntu-incident-response-toolkit/
├── bin/
│   └── uir                         # user-facing executable
├── lib/
│   ├── cli.sh                      # argument parsing and dispatch
│   ├── config.sh                   # defaults and validated settings
│   ├── validate.sh                 # safe ID/field/path validation
│   ├── collect_host.sh             # host diagnostics
│   ├── collect_service.sh          # service + journal diagnostics
│   ├── sanitize.sh                 # storage/export redaction rules
│   ├── incident_store.sh           # create/read/search
│   ├── compare.sh                  # before/after change summary
│   ├── export.sh                   # archive, manifest, verification
│   └── retention.sh                # quotas and safe pruning
├── config/
│   └── example.conf
├── tests/
│   ├── unit/                       # Bats: fixture-driven, no root
│   ├── integration/                # Ubuntu VM tests
│   └── fixtures/                   # synthetic sanitized logs
├── lab/
│   ├── setup/
│   └── incidents/                  # reproductions + undo steps
├── docs/
│   ├── architecture.md
│   ├── security.md
│   ├── operations.md
│   ├── kb/
│   └── incidents/
├── examples/
│   └── sanitized/                  # selected publishable samples
├── .github/
│   └── workflows/                  # activate after GitHub push
├── README.md
├── LICENSE
├── CHANGELOG.md
└── .gitignore
```

The eventual README is written throughout the project and polished at release. The public repository is created/pushed **after local implementation and verification**, consistent with the requested workflow.

---

## 6. Evidence model and data storage

### 6.1 Default local data directory

Use a private per-user data location, provisionally:

```text
~/.local/share/ubuntu-irt/
├── config/
├── incidents/
│   └── INC-007/
│       ├── incident.json
│       ├── timeline.jsonl
│       ├── before/
│       │   ├── snapshot.json
│       │   ├── journal.jsonl.gz
│       │   └── diagnostics.txt.gz
│       ├── after/
│       │   ├── snapshot.json
│       │   ├── journal.jsonl.gz
│       │   └── diagnostics.txt.gz
│       ├── comparison.json
│       └── report.md
└── exports/                      # only if operator requests local export retention
```

This is an **illustrative format contract**, not a promise to produce these files before their milestones. The data directory is separate from the repository and is ignored by Git.

### 6.2 Schema design

An incident metadata record should include:

- `schema_version`, validated `incident_id`, creation/update timestamps in UTC (ISO 8601), host pseudonym/OS, service, severity, status, symptom and reproduction method.
- Detection/response/restoration timestamps where measurable, each with explicit source and timezone.
- Before/after snapshot references, collector results and their return status; a failure to collect one source must not be disguised as successful capture.
- Hypotheses, root cause, operator remediation notes, verification checks, timeline events, and KB reference.
- Redaction policy version, retention policy and archive/manifest hashes when generated.

Use **JSON** for metadata and comparable snapshots, **JSON Lines** for time-ordered events, **Markdown** for readable reports and **gzip** for bulky text/JSONL logs. `jq` should construct and query structured JSON safely. Store timestamps uniformly in UTC, display local time only in the UI/report as a clearly identified view.

### 6.3 Compression and export format decision

- **Default internal storage:** `.jsonl.gz` and `.txt.gz` for large captured excerpts; JSON files remain uncompressed when convenient for frequent small reads.
- **Export:** standards-friendly `.tar.gz` archive, containing a minimal sanitized evidence set, readable report and checksums.
- **Optional future optimization:** benchmark `zstd` before adopting it. It may compress faster or smaller for some workloads, but requires an additional dependency and can reduce portability. There is no universally smallest format for all logs.
- **Never archive** arbitrary absolute paths, symbolic links, device files or `../` path traversal. Before creating or extracting an archive, validate file types and member paths.

### 6.4 Retention policy (initial proposal)

| Setting | Proposed default | User control |
| --- | --- | --- |
| Incident retention | **30 days** | Configurable positive number of days |
| Total managed store size | **500 MiB** | Configurable bounded quota |
| Per-capture log excerpt | **10 MiB** maximum | Can lower; increase only within configured global cap |
| Collection time window | Recent bounded journal window | Choose start/end with upper limits |
| Deletion | **Dry-run first** | Explicit `--yes` for actual prune |
| Automatic pruning | Off until explicitly configured | Optional scheduled run after tests |
| Export lifetime | Operator-managed separately | Export is never silently deleted by internal incident pruning |

The app must reject invalid/unbounded retention settings that would permit uncontrolled growth; warn when the store is approaching quota. When the cap is reached, fail safely with actionable guidance rather than deleting evidence without warning. Show the list of records to be deleted before a prune. Deletion should be confined to validated incident directories and resist symlink/traversal tricks.

**What user control means:** The operator can choose retention length, decide when to create a snapshot, decide whether and where to export it, and explicitly prune or preserve a selected incident under a documented policy. A later 'pinned incident' feature may be considered if we need policy exceptions; it must still obey a size ceiling.

---

## 7. Security and privacy design

1. **Private files:** create the data root with permissions `0700`, files with `0600`, and apply `umask 077`; audit actual permissions in automated tests.
2. **Least privilege:** core CLI runs as the regular user. Privileged information uses carefully scoped, documented `sudo` reads or purpose-built collector wrappers; never require `sudo` for the entire CLI. Permission-denied diagnostics must degrade gracefully.
3. **Read-only first:** `capture`, `search`, `compare` and `export` do not change service or OS configuration. Troubleshooting fixes happen as documented manual lab steps.
4. **Parameter allowlisting:** validate incident IDs, service unit names, output paths, integer limits and date arguments; reject embedded shell metacharacters, path separators and ambiguous identifiers.
5. **Redaction before local persistence where feasible; always before export:** avoid collecting high-risk sources by default. Apply documented, tested redaction rules to bounded output. Check credentials, tokens, private keys, email addresses and sensitive user identifiers. Do not make blanket substitutions that erase ports, error codes or other essential context.
6. **Human review prior to public sharing:** automated redaction reduces risk but cannot guarantee that every secret is removed. `export` should support a manifest/preview and strongly warn before sharing.
7. **Safe archiving:** use a private staging directory; reject symlinks/special files; avoid accidental file inclusion; produce SHA-256 checksums for each exported payload and a documented verification procedure.
8. **No log-content execution:** never interpolate diagnostic text into a shell command. Treat filenames and log lines as hostile data.
9. **Resource safety:** bound command runtime, bytes captured, records returned and export size; clean temporary files on interrupt/failure; verify available disk space.
10. **Auditable actions:** record configuration changes, captures, exports and retention deletions without recording secrets in the audit trail.
11. **No telemetry by default:** no remote uploads, network calls, cloud APIs or third-party collection in v1.0.
12. **No destructive demonstrations outside VM:** any fault injection must include a precondition check, rollback, and safe test scope.

### 7.1 Security tests that cannot be skipped

- [ ] Invalid incident ID such as `../outside` is refused.
- [ ] Service argument containing command substitution or shell metacharacters is rejected without execution.
- [ ] Symlink planted in a candidate incident/export directory is not followed.
- [ ] Sensitive fixture strings do not appear in sanitized public export.
- [ ] Private file modes and `umask` are correct after create/capture/export.
- [ ] Permission-denied journal/source returns a diagnostic warning, not a crash or false success.
- [ ] Capture stops at byte/time limits and leaves no partial record marked as complete.
- [ ] Truncated/corrupt gzip input or JSON metadata is detected and reported.
- [ ] Retention dry-run performs no deletions; actual prune touches only intended managed records.
- [ ] Export archive members contain no absolute paths, traversal paths or symlinks.

---

## 8. Incident lab: 12 proposed cases

Every lab scenario has four artifacts: **(a)** documented safe reproduction, **(b)** before snapshot, **(c)** human-written RCA and repair/verification, **(d)** after snapshot plus KB article. These are controlled VM incidents; never imply a customer outage actually happened.

| ID | Incident / user-visible symptom | Safe fault to stage in isolated VM | What proves resolution |
| --- | --- | --- | --- |
| **INC-001** | Custom systemd service cannot start | Deliberately incorrect `ExecStart` in a disposable training unit | `systemctl` active state + expected local process behavior |
| **INC-002** | SSH connection cannot be established | Break a *lab-only* SSH setting with console fallback; inspect `ssh.socket` / `ssh.service` | Successful SSH from host plus healthy relevant unit/socket |
| **INC-003** | Web content returns permission denied | Change permissions on a disposable Nginx document fixture | `curl` returns expected content and no permission error |
| **INC-004** | Package management operation fails | Reproduce a controlled package lock/dependency issue in the VM; use fixture-based tests if unsafe to stage | Package manager health restored; diagnostic logs understood |
| **INC-005** | CPU load spike slows service | Short, bounded, lower-priority test workload with forced timeout | Workload stops; load/process snapshot normalizes |
| **INC-006** | Disk space alert or failed write | Fill only a dedicated quota-limited test filesystem, **not the guest root disk** | Test filesystem recovered; writes succeed again |
| **INC-007** | **Nginx service unavailable** (high severity) | Invalid Nginx configuration or dedicated test port collision | `nginx -t`, active unit, expected listener, successful `curl` |
| **INC-008** | Nginx reverse proxy returns upstream error | Stop a disposable local upstream test service | Upstream and proxy respond correctly; 5xx eliminated |
| **INC-009** | Name resolution fails for a test dependency | Use isolated test DNS configuration/fixture without cutting off host access | Deterministic DNS lookup and dependent test succeed |
| **INC-010** | HTTP access blocked by firewall | Temporary, narrow VM-local firewall rule with console fallback | Connection works after rule removal; ruleset verified |
| **INC-011** | Expected service logs not visible | Training service emits logs under a different unit/context; diagnose selector or journal persistence settings | Logs found through the right unit/time/boot filters |
| **INC-012** | A service fails because its dependency is unavailable | Disposable systemd service requiring another test unit | Correct start ordering and healthy dependent service |

**Risk controls:** INC-002 and INC-010 require VM console access and saved snapshot; INC-006 must use a separate bounded filesystem; INC-005 must use a timeout and low priority. If any fault cannot be staged safely, use clearly labeled **synthetic log fixtures** and explain the limitation honestly.

### 8.1 Detailed case-study format

Each incident file `docs/incidents/INC-XXX.md` should use the same template:

```text
Incident ID / title / date / severity / environment
Reported symptom and impact (simulated)
Detection source and initial health check
Timeline (UTC)
Initial hypotheses and triage priority
Commands used, their purpose, and actual observed output
Evidence links (sanitized; before snapshot)
Root cause and why alternative hypotheses were ruled out
Corrective action and potential risks
Post-fix verification (after snapshot + concrete assertions)
Customer-facing resolution summary and handoff note
Preventive measure / monitoring suggestion
Knowledge-base article link
What was learned; remaining limitations
```

### 8.2 INC-007 worked design example

**Scenario:** An employee cannot access an internal web application because Nginx is unavailable. **Severity:** high *within the simulated lab*.

**Pre-check:** The service and test page were healthy before fault injection; a clean VM snapshot exists.

**Initial investigation commands:**

```bash
systemctl status nginx
journalctl -u nginx -n 50 --no-pager
sudo nginx -t
sudo ss -tulpn
curl -fsS -I http://127.0.0.1/
```

**Toolkit behavior:** Create `INC-007`, capture a bounded pre-fix record, preserve the actual evidence and failed checks, and report collection errors independently. The operator identifies whether this lab instance is a configuration error or port collision, applies a targeted manual fix, and captures the post-fix record. `uir compare` highlights changes (service state, listener, Nginx test and HTTP response). `uir export` prepares a sanitized, compressed bundle with the incident report and checksums.

**Acceptance:** The before snapshot unambiguously records the failure; the after snapshot proves Nginx is functioning; comparison is accurate; exported evidence is readable; archive contains no known seeded secrets; recovery is repeatable.

---

## 9. Collection and diagnostic design

### 9.1 Host-wide bounded diagnostics

- Host identity: Ubuntu release, kernel, hostname pseudonym, boot ID or other non-secret correlation identifier, UTC timestamp.
- Resource health: uptime/load, memory/swap, disk space/inodes and a bounded process snapshot.
- Networking: IP interface state, routing summary, local listening sockets, and optional focused DNS/connectivity checks.
- Service: systemd active/failed/sub-state, unit files/drop-in information, recent journal entries and a service-specific *read-only* diagnostic check.
- Kernel/package clues when applicable: bounded `dmesg` (if permitted), relevant apt/dpkg logs and AppArmor denials (if accessible).

### 9.2 Smart selection, not indiscriminate dumping

Each incident selects an **allowlisted service profile** (e.g., Nginx, SSH, generic systemd unit). Collectors should choose relevant information, impose output/time limits, and explain absent files or permissions. Modern Ubuntu log configuration can vary, so tools must not assume a specific `/var/log/auth.log` or `/var/log/syslog` file always exists.

### 9.3 Failure and partial-result model

Capture status is one of `complete`, `partial`, or `failed`. Each collector independently reports its source, timestamp, elapsed time, exit code and error message. A missing optional log produces a **partial** capture, not silently manufactured evidence.

### 9.4 Pre/post comparison semantics

Compare structured fields when possible: service state, active state timestamp, open port presence, available disk/inodes, load and memory, key error signatures and HTTP check outcome. Keep numeric measurements unit-labeled. Text-only journal diffs are secondary because time-sensitive lines change even without fixes. Clearly distinguish observed change from inferred causality.

---

## 10. Development method and milestones

**Working agreement:** Each milestone has one narrow implementation goal; I explain each command and why it is needed, give a test, inspect the actual output/error, correct defects before continuing, and record the final passing result. No step is called complete without a demonstrated acceptance check. If something fails, debug and **resume from the failed checkpoint**, not from the beginning. Do not create or push the public GitHub repository until the local MVP is ready.

| Milestone | Implement in this increment | Required verification / exit gate |
| --- | --- | --- |
| **M0 — Design approval** | Confirm scope, naming, defaults, data model and threat boundaries | Sign off this blueprint; list decisions and non-goals |
| **M1 — Safe Ubuntu lab** | VirtualBox Ubuntu 24.04 LTS, Nginx, SSH, tools and base snapshot | Version, guest console, service access, VM restore confirmed |
| **M2 — CLI skeleton** | `uir --help`, `--version`, `doctor`, argument parser, explicit exit codes | Bash syntax + ShellCheck + manual valid/invalid CLI checks |
| **M3 — Secure local data store** | `init`, config validation, incident ID rules, private directories, JSON schema | Bats tests for modes, persistence, bad IDs, injection and symlinks |
| **M4 — Host diagnostics** | Health collectors with bounded output, error and timeout handling | Fixture tests + real VM capture compared to direct commands |
| **M5 — Service diagnostics** | Nginx/SSH/systemd profiles and time-bounded journal collection | Healthy/failed service tests; `ssh.socket` case; partial-capture behavior |
| **M6 — Persistent capture/search** | Incident lifecycle, before/after store, gzip evidence, filters | Reopen after CLI restart/reboot; search finds known test log; gzip round-trip |
| **M7 — Comparison/report** | Structured comparison, timeline, Markdown incident report template | Controlled failure-to-fix scenario produces correct differences |
| **M8 — Secure export** | Redaction, preview, manifest hashes and sanitized `.tar.gz` archive | Inject known sensitive fixtures; no known leaks; archive path/hash tests |
| **M9 — Retention and quotas** | Retention settings, disk cap, prune dry-run/confirm, cleanup errors | Dry-run unchanged; exact target pruned; pinned/outside folders untouched; quota honored |
| **M10 — Twelve lab incidents** | Stage, analyze, fix and document each scenario sequentially | Every case has before/after evidence, verified fix, RCA and KB article |
| **M11 — Release hardening** | Full tests, negative cases, usability pass, packaging and install/uninstall docs | Fresh VM smoke test, clean lint/test suite, accurate limitations |
| **M12 — Portfolio publication** | Public sanitized examples, polished README, license, GitHub repository and push | Independent install/use walkthrough succeeds; repo has no secret/internal files |
| **M13 — Optional monitoring (v1.1)** | Opt-in allowlisted service-failure capture and rate limiting | Controlled failure generates one bounded snapshot; disable and no-loop verified |
| **M14 — GUI (v2.0)** | Design dashboard over validated incident store/API | UI mirrors tested CLI functions and preserves security boundaries |

### 10.1 Checkpoint log template

For each finished increment record:

```text
Milestone:
Feature/behavior implemented:
Files changed:
Commands executed:
Expected result:
Actual result:
Tests passed / tests failed:
Defect and fix (if any):
Security/reliability checks:
Git commit ID (after local Git is initialized):
Decision: PASS / BLOCKED
Next approved increment:
```

### 10.2 Local Git workflow

Initialize a **local Git repository during development** to make small, traceable commits and recover regressions. Defer **creating the GitHub remote and pushing** until release preparation, as requested. Make one focused commit per verified milestone; no secrets, captured private logs or VM disk images in Git. Release the final public repository only after reviewing all tracked files.

---

## 11. Test strategy and definition of done

### 11.1 Tests by layer

- **Syntax/style:** `bash -n`, `shellcheck`, `shfmt` validation for each Bash module.
- **Unit tests:** Bats tests for input validation, serialization, size limits, redaction rules, dates, search, retention and export handling using synthetic fixture data.
- **Integration tests:** Collect from real Nginx/SSH/systemd services in the Ubuntu VM; verify permission behavior and compare direct OS evidence to stored data.
- **End-to-end tests:** One full incident from creation to before capture, manual fix, after capture, search, compare and sanitized export.
- **Safety/abuse tests:** Untrusted text injection, path traversal, symlink refusal, interrupted capture, corrupt gzip, missing dependencies, stale incident metadata, permissions, low space and cleanup.
- **Release smoke test:** Fresh Ubuntu 24.04 VM with no prior toolkit data installs and uses the published instructions successfully.

### 11.2 Operational quality targets (proposed, not measured)

1. All essential scenarios and CLI paths have at least one automated test; security-critical flows have both positive and negative tests.
2. No known high-severity security defects, command injection or path traversal at release.
3. Every collector reports failures honestly and respects configured byte/time bounds.
4. There are no unhandled errors in the standard clean-VM path.
5. Full incident evidence can be recovered from local storage and independently verified from a `.tar.gz` export.
6. Each of the 12 case studies contains reproducible diagnostic reasoning, a real verification check, and an accurate simulated-lab disclosure.
7. No public archive, README screenshot or example log contains actual secrets or personal identifiers.

**Definition of done for v1.0:** M0–M12 pass, the user has completed the hands-on procedures, the fresh-VM walkthrough works, the repository has been reviewed for leaks, and the README accurately describes all tested features. Optional monitoring and GUI do **not** delay v1.0.

---

## 12. Documentation and publication plan

### 12.1 README contents (designed from the first milestone; polished at the end)

1. Professional project name, concise problem statement and supported use cases.
2. Plain-English architecture diagram and data flow.
3. Clear scope, current version and known limitations.
4. Tested Ubuntu version, prerequisites and compatibility caveats.
5. Step-by-step installation and uninstallation instructions with safe defaults.
6. Quickstart demonstrating **real** CLI commands and **actual** sanitized outputs.
7. Worked `INC-007` story: symptom → evidence → diagnosis → repair → before/after → export.
8. CLI command reference and example configuration.
9. Storage locations, log compression, privacy and data-retention controls.
10. Incident catalog and KB links; screenshot/terminal-demo assets if useful.
11. How to run syntax checks, unit tests and VM integration tests.
12. Troubleshooting, security model and responsible limitations.
13. STAR-aligned engineering summary with **verified metrics only**.
14. License, contribution guidance, project roadmap and changelog.

### 12.2 Publishable evidence versus material that stays private

**Publish:** Synthetic or thoroughly sanitized logs, redacted sample incident archives, mock employee incident intake, reproducible scenario setup, report examples, test results, system-state evidence without sensitive IDs, architecture, command transcripts and case studies.

**Never publish:** Live SSH private keys, passwords, access tokens, machine-specific private networking, personal accounts, confidential customer or school information, raw auth logs, host VM disk, or internal evidence containing real identifying details.

### 12.3 Optional project demonstration

A brief terminal screencast or annotated GIF can show `uir doctor`, creation of `INC-007`, pre-fix evidence, manual remediation, comparison, and export. The demo should be short enough for a recruiter to scan and technical enough for an engineer to inspect.

---

## 13. Resume and interview evidence plan

Draft resume bullets **only after the application actually works**. Provisional wording to be verified later:

- Developed a modular Bash incident-response CLI for Ubuntu 24.04 LTS to collect bounded systemd/service diagnostics, preserve compressed incident records, and generate sanitized support handoff archives.
- Reproduced and resolved **12 isolated Linux service/host incidents**, documenting RCA, before-and-after verification, customer-facing summaries and knowledge-base articles.
- Implemented automated Bash tests and security controls covering input validation, permissions, sensitive-log redaction, archive integrity and configurable evidence retention.

The first two bullets describe *intended outcomes*, not completed achievements at this stage. Later replace general phrases with measured evidence: test count, incident count actually completed, storage savings observed and verified user workflow duration. Explain design choices—why `jq`, why gzip, why no default auto-remediation, how redaction is tested—without implying the code was written without outside assistance.

### 13.1 Suggested interview talking points

- How an Nginx symptom differs from a root cause and what `nginx -t`, `journalctl`, `ss` and `curl` each establish.
- Why the `ssh.socket` versus `ssh.service` distinction matters on Ubuntu 24.04.
- How least privilege and bounded capture prevent a diagnostic tool from worsening incidents.
- How JSON metadata plus compressed logs help both humans and scripts.
- Why a post-remediation snapshot must include an explicit functional check, not only `systemctl active`.
- How partial failure, missing permissions and unreadable logs are surfaced honestly.
- What would need to change before supporting multi-host or production deployment.

---

## 14. Risks and mitigations

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Project expands too far | No finished, reviewable CLI | Lock v1.0 to local host + 12 incidents; move monitoring/GUI to later versions |
| VM overconsumes the host | Poor development experience | Begin with 2 GB/2 vCPU; monitor real usage; keep one VM active |
| Testing breaks host access | Loss of SSH/network connectivity | VM console and base snapshot; NAT; no production/host fault injection |
| Disk-filling demo damages guest OS | Data corruption or boot problems | Dedicated bounded filesystem; restore route and explicit safety guard |
| Logs leak secrets | Privacy/security breach | Minimize collection, redact, restrict modes, preview exports, manually inspect public samples |
| Archive/path bugs | Overwrite or data exposure | Validate IDs/paths, refuse symlinks and dangerous archive members, test adversarial fixtures |
| Misleading test success | False confidence | Exit codes, capture status, fresh VM checks and independently reproduced outcomes |
| Hard-to-maintain monolithic Bash | Fragility and low interview credibility | Small modules, consistent contracts, ShellCheck, Bats, explicit failures |
| Unsupported metrics in resume | Credibility issue | Measure and disclose only outcomes shown by tests or demo logs |

---

## 15. Decisions awaiting your review

I have supplied practical defaults so that the plan remains usable **without blocking progress on unanswered questions**. Please review these decisions before M1:

| Decision | Suggested default | What can be changed |
| --- | --- | --- |
| **D-01: Platform** | Ubuntu Server 24.04 LTS in VirtualBox | A different local hypervisor if needed |
| **D-02: v1.0 scope** | One Ubuntu VM/host, local CLI; GUI deferred | Multi-host and UI scope should remain v2.0 |
| **D-03: CLI name** | `uir`; repo `ubuntu-incident-response-toolkit` | Choose a distinct brand/name before coding |
| **D-04: Saved evidence** | Metadata JSON, journal JSONL gzip, diagnostic text gzip, `.tar.gz` export | Compression choice can be benchmarked after first tests |
| **D-05: Retention** | 30 days, 500 MiB total store, 10 MiB per capture | User-configurable bounded values |
| **D-06: Privileges** | CLI as normal user with narrow privileged reads when essential | Must remain least-privilege |
| **D-07: Monitoring** | Not required for v1.0; add opt-in in v1.1 | Can reconsider once CLI has reliable tests |
| **D-08: Publication** | Local Git commits throughout; GitHub remote and public push only at release | Can move earlier if needed for private backup, but no raw logs in Git |

**Four focused review questions:**

1. Do you approve the **v1.0 boundary** (one local Ubuntu host, Bash CLI, persistent storage, search, compare, sanitization, retention and export; optional monitoring + GUI later)?
2. Should incident data default to **30 days / 500 MiB**, with user-adjustable bounded retention, or do you want different defaults?
3. Do you prefer the short CLI command **`uir`**, or should we choose a more distinctive final command name now?
4. Would you like the incident KB articles written in a **support-ticket style** (customer impact, updates, SLA-style prioritization, handoff) as proposed? This is recommended for Canonical alignment.

None of these questions requires us to claim that a capability is already implemented. Once the scope and defaults are reviewed, the next step is **M1 — VM baseline and recovery verification**, followed by **M2 — a minimal working CLI skeleton**. Implementation proceeds one tested increment at a time.

---

## 16. Authoritative references and tooling

These references inform the design; their inclusion does not imply this toolkit is endorsed by Canonical or any upstream project.

- [Ubuntu Server documentation — package management](https://ubuntu.com/server/docs/how-to/software/package-management/)
- [Ubuntu 24.04 LTS release notes](https://documentation.ubuntu.com/release-notes/24.04/) — includes the OpenSSH socket activation details.
- [Ubuntu tutorial — viewing and monitoring log files](https://ubuntu.com/tutorials/viewing-and-monitoring-log-files)
- [Ubuntu Security documentation — automatic security updates](https://documentation.ubuntu.com/security/security-updates/)
- [Ubuntu journald configuration manual](https://manpages.ubuntu.com/manpages/noble/man5/journald.conf.5.html)
- [Ubuntu Security documentation — AppArmor](https://documentation.ubuntu.com/security/security-features/privilege-restriction/apparmor/)
- [ShellCheck project](https://github.com/koalaman/shellcheck)
- [Bats-core automated Bash testing](https://github.com/bats-core/bats-core)
- [Canonical Cloud Support Engineer role description](https://canonical.com/careers/2456563/linux-support-engineer-amer-remote)

---

## 17. Version-control and review record

| Version | Status | Change |
| --- | --- | --- |
| `v0.1-plan` | **Draft, awaiting user review** | Converted initial requirements into architecture, functional specifications, security model, 12 incident scenarios, milestone gates, test plan, and publication criteria |

**Important distinction:** This document is a **build plan**; it contains no claim that the CLI, test suite, incident evidence or GitHub repository already exists. We will implement and validate those artifacts in the agreed order.
