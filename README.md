<div align="center">

# Ubuntu Incident Response Toolkit

### Investigate Linux incidents. Preserve the evidence. Explain the resolution.

**A modular Bash CLI for Ubuntu 24.04 incident triage, bounded diagnostics, structured comparisons, searchable evidence, and sanitized handoffs.**

`Bash` · `systemd` · `journalctl` · `jq` · `gzip` · `SHA-256` · `Bats` · `Ubuntu Server`

**Release: v1.0.0-rc1 — feature-complete candidate; Ubuntu VM incident acceptance pending**

[Quickstart](#quickstart) · [Workflow](#an-end-to-end-incident-workflow) · [Security](#security-by-design) · [Tests](#testing-and-quality-gates) · [Incident catalog](#incident-lab-catalog) · [Architecture](docs/architecture.md)

</div>

---

## Why this exists

Investigating a Linux incident usually involves switching between `systemctl`, journal logs, network listeners, disk and memory health, application checks, and a written ticket. The evidence is easy to scatter or accidentally share before it has been sanitized.

**UIR makes evidence collection systematic without automating risky repairs.** A support engineer tracks an incident, captures a time-bounded **before** snapshot, makes a carefully reviewed correction in an isolated lab, records the **after** snapshot, compares objective changes, and creates a compressed handoff that is easier to verify and review.

This is a **local, single-host training and portfolio tool**. It is not sponsored by Canonical, does not replace a production monitoring stack, and does not assert that simulated incidents were real customer outages.

## What is included

| Capability | v1.0 candidate | Why it matters |
| --- | --- | --- |
| Host preflight | ✅ Implemented | Shows missing dependencies, read-only journal access and WSL caveats |
| Persistent incident lifecycle | ✅ Implemented | Unique IDs, severity, service, UTC timestamps, notes and status |
| Bounded host observations | ✅ Implemented | Uptime, CPU load, memory, disk/inodes, network context |
| Targeted service diagnosis | ✅ Implemented | Nginx, SSH/socket and disposable `uir-*` training units |
| Immutable before/after captures | ✅ Implemented | Bounded journal excerpts, gzip diagnostics, explicit partial status |
| Literal search | ✅ Implemented | Filters incident metadata and searches compressed evidence safely |
| Structured comparison | ✅ Implemented | Highlights measured state changes, not invented causality |
| Human-readable case report | ✅ Implemented | Separates operator notes from observed evidence |
| Sanitized `.tar.gz` handoff | ✅ Implemented | Fixed archive membership, public redaction and SHA-256 manifest |
| User-controlled retention | ✅ Implemented | Configurable age/size limits and explicit dry-run/prune |
| Incident labs and KB drafts | 📖 Prepared | 12 scenario runbooks and 12 troubleshooting knowledge-base articles |
| VM fault reproduction | ⏳ Pending | Real Ubuntu VirtualBox tests with verified recovery remain to be executed |
| Service failure monitoring, GUI | — Deferred | v1.1 and v2; out of scope for this release |

*“Implemented” means source code and isolated synthetic integration tests exist; it does not imply production qualification or that all VM scenarios were performed.*

## Architecture at a glance

```text
Ubuntu support engineer
       |
       v
   bin/uir  ── input/schema validation ── private incident records
       |                                           ^
       +── host collector ──────────────────────────┤
       +── service/journal collector ─ redaction ─ gzip
                                                   |
                                     search / compare / report
                                                   |
                                       explicit export preview
                                                   |
                                 public-redact + SHA-256 manifest
                                                   |
                                       portable .tar.gz handoff
```

Detailed [architecture, data schema and trust boundaries](docs/architecture.md) explain design trade-offs and limitations.

## Requirements

- **Ubuntu Server 24.04 LTS** — target platform; a disposable **VirtualBox VM** is recommended for all fault-injection labs.
- 2 vCPU / 2 GiB RAM / 25 GiB virtual disk is a suggested starting point, not a measured minimum.
- Bash 5, GNU coreutils, `jq`, `gzip`, `tar`, `timeout`, `flock`, `ip`, `ss`, `systemctl`, `journalctl`, `sha256sum`.
- Recommended verification tools: `shellcheck`, `shfmt`, `bats`.
- Nginx and OpenSSH Server for the service-specific lab exercises.

> **WSL note:** WSL Ubuntu 24.04 is useful for editing and non-destructive tests. Do not run deliberately broken SSH, firewall, DNS or disk-exhaustion incidents inside your everyday WSL distro. For a real incident lab use the isolated Ubuntu VM and take a `CLEAN-BASELINE` snapshot first. Keep the repository and runtime store on the Linux filesystem (`~/projects/...`), not under `/mnt/c`.

## Quickstart

The repository remains local until user-verified tests and privacy review are complete. Unpack the **single full release package** once, or clone it after it is published.

```bash
sudo apt update
sudo apt install -y jq gzip tar coreutils iproute2 curl shellcheck shfmt bats

# Inside your Ubuntu project directory:
chmod +x bin/uir
./bin/uir --help
./bin/uir --version
./bin/uir doctor
./bin/uir init
```

**Optional user-local command installation** (keeps files in the one project folder; does not copy code into multiple version folders):

```bash
mkdir -p "$HOME/.local/bin"
ln -s "$(pwd -P)/bin/uir" "$HOME/.local/bin/uir"
# Ensure ~/.local/bin is on PATH for future shells, then use: uir doctor
# To uninstall, first verify the symlink target with: readlink ~/.local/bin/uir
# Remove only that symlink: rm "$HOME/.local/bin/uir"
```

The symlink target must remain inside the repository; moving the project breaks it until relinked. Uninstalling the command does **not** automatically erase private incident evidence.

The runtime data is created at `~/.local/share/ubuntu-irt/`, unless `XDG_DATA_HOME` is set. Do **not** run `sudo ./bin/uir` and do **not** copy raw logs into this repository.

## An end-to-end incident workflow

The example ID `INC-007` describes a **simulated Nginx outage on a disposable VM**; actual remediation is deliberately manual.

```bash
# 1. Open a case
./bin/uir incident create --id INC-007 --service nginx --severity high \
  --summary 'Simulated Nginx unavailable in the Ubuntu training lab'
./bin/uir incident status --id INC-007 --value investigating

# 2. Reproduce the isolated lab issue safely (separate VM exercise)
#    Follow lab/incidents/INC-007.md; do NOT copy its fault commands into WSL.

# 3. Capture bounded pre-fix evidence
./bin/uir capture --incident INC-007 --phase before --minutes 15
./bin/uir incident note --id INC-007 --kind hypothesis \
  --text 'Hypothesis after inspecting actual unit and journal output'

# 4. Manually repair the dedicated lab fault, following the runbook

# 5. Record the outcome
./bin/uir capture --incident INC-007 --phase after --minutes 15
./bin/uir compare --incident INC-007
./bin/uir incident note --id INC-007 --kind root_cause \
  --text 'Replace with the confirmed cause backed by evidence'
./bin/uir incident note --id INC-007 --kind verification \
  --text 'Replace with observed nginx -t and curl results'
./bin/uir incident status --id INC-007 --value resolved
./bin/uir report --incident INC-007

# 6. Find and safely hand off
./bin/uir incident search --service nginx --text 'address already in use'
./bin/uir export --incident INC-007 --preview
./bin/uir export --incident INC-007 --output ./INC-007-handoff.tar.gz
```

Incident IDs must be unique (`INC-007`, `INC-008`, etc.). `before` and `after` snapshots are **immutable**. Repeating a lab means creating a new incident, not overwriting prior evidence.

### Capture content

```text
~/.local/share/ubuntu-irt/
├── config/settings.json               # 0600
└── incidents/                          # 0700
    └── INC-007/                        # 0700
        ├── incident.json              # incident metadata + operator notes
        ├── before/
        │   ├── snapshot.json          # structured UTC observations
        │   ├── diagnostics.txt.gz      # bounded, locally redacted text
        │   └── journal.jsonl.gz       # bounded, locally redacted journal
        ├── after/ ...                  # same schema
        ├── comparison.json            # observation-only delta summary
        └── report.md                  # human-readable assessment
```

Gzip is a portable and space-efficient default for repetitive logs; small JSON files remain uncompressed for easy inspection. The local store is kept **separate** from the public Git repository.

### Searching and evidence retention

```bash
./bin/uir incident list
./bin/uir incident show INC-007
./bin/uir incident search --since 2026-11-01 --severity high
./bin/uir incident search --text 'connection refused'

./bin/uir retention status
./bin/uir retention set --days 30 --max-storage-mb 500 --capture-max-mb 10
./bin/uir retention prune --dry-run
# After inspecting exact deletion candidates:
./bin/uir retention prune --yes
```

Default policy: **30 days**, **500 MiB total managed incident storage**, **10 MiB per compressed capture**. There is **no automatic pruning** or silent deletion; exported archives have their own lifetime and are not removed by `retention prune`.

## Secure, portable support handoff

`uir export --preview` lists the allowlisted contents without generating an archive. The export pipeline re-sanitizes text, packages selected metadata, available before/after evidence, comparison, an operator report and a **SHA-256 checksum manifest** into a `.tar.gz` file.

After checking archive members and extracting only into a private review folder:

```bash
(cd ~/uir-review && sha256sum -c SHA256SUMS)
```

**Integrity is not anonymity.** Automated redaction cannot reliably identify every credential, IPv6 address, customer name or subtle identifier. Inspect report, JSON and decompressed logs before making any archive public. Export never uploads files for you and refuses to overwrite existing destinations.

## Testing and quality gates

```bash
bash tests/run-all.sh
```

The suite is designed to run as a regular user. It includes syntax/optional lint checks, baseline smoke tests, Bats tests, insecure-path and duplicate protections, gzip round-trips, metadata persistence, comparison, search, redaction, safe archive hashes and non-destructive retention checks.

**Verified in the build container:** A synthetic end-to-end integration run passed 28 checks as of this candidate. This does **not** establish Ubuntu VM or service-remediation success. Individual tests and the count can change after further hardening; record the exact final run results in [`docs/testing.md`](docs/testing.md) rather than inventing performance statistics. ShellCheck, shfmt and Bats results must still be verified on the intended Ubuntu environment.

## Incident lab catalog

Twelve isolated or fixture-first training exercises, with separate step-by-step fault/diagnosis/repair/cleanup runbooks and troubleshooting KB drafts:

| Incident | Focus | Runbook | KB |
| --- | --- | --- | --- |
| INC-001 | systemd ExecStart failure | [Lab](lab/incidents/INC-001.md) | [KB](docs/kb/KB-001.md) |
| INC-002 | Secondary SSH configuration failure | [Lab](lab/incidents/INC-002.md) | [KB](docs/kb/KB-002.md) |
| INC-003 | Web file permissions | [Lab](lab/incidents/INC-003.md) | [KB](docs/kb/KB-003.md) |
| INC-004 | Package lock diagnostics (fixture-first) | [Lab](lab/incidents/INC-004.md) | [KB](docs/kb/KB-004.md) |
| INC-005 | Bounded CPU load | [Lab](lab/incidents/INC-005.md) | [KB](docs/kb/KB-005.md) |
| INC-006 | Capped tmpfs disk exhaustion | [Lab](lab/incidents/INC-006.md) | [KB](docs/kb/KB-006.md) |
| INC-007 | Nginx invalid configuration | [Lab](lab/incidents/INC-007.md) | [KB](docs/kb/KB-007.md) |
| INC-008 | Nginx upstream 502 | [Lab](lab/incidents/INC-008.md) | [KB](docs/kb/KB-008.md) |
| INC-009 | DNS lookup failure (fixture-first) | [Lab](lab/incidents/INC-009.md) | [KB](docs/kb/KB-009.md) |
| INC-010 | Firewall rule behavior (fixture-first) | [Lab](lab/incidents/INC-010.md) | [KB](docs/kb/KB-010.md) |
| INC-011 | Journal unit vs tag selection | [Lab](lab/incidents/INC-011.md) | [KB](docs/kb/KB-011.md) |
| INC-012 | systemd missing dependency | [Lab](lab/incidents/INC-012.md) | [KB](docs/kb/KB-012.md) |

**Status:** All twelve lab **runbooks are drafted, not yet executed**. After hands-on exercises, actual evidence and results belong in [the incident execution tracker](docs/incidents/STATUS.md) and individual case-study records based on the [template](docs/incidents/TEMPLATE.md). A fictional RCA is not acceptable portfolio evidence.

## Security by design

- **Least privilege:** regular-user CLI; no implicit `sudo`.
- **Controlled scope:** allowlisted services, recent journal window, timeouts, byte bounds, no arbitrary command execution.
- **Private evidence:** owner-only files/directories, validated IDs/paths, no state in the Git checkout.
- **Traceable records:** UTC timestamps and explicit `partial` versus `complete` collector outcome.
- **Defensive archives:** explicit membership, sanitized staging, SHA-256 digests, no overwriting existing output.
- **Deletion requires confirmation:** per-user retention with `--dry-run` and `--yes`.

**Known limitations:** Bash filesystem checks are not atomic security boundaries against a hostile process acting as the same UNIX user. Human audit remains mandatory because regex-based redaction is not comprehensive. The service profile does not guarantee it captures every application port or end-to-end request. Live journal access varies by host, and WSL behavior differs from a full Ubuntu VM. More details: [security model](docs/security.md).

## Engineering decisions and roadmap

- **Bash + jq**: inspectable on Ubuntu, no heavyweight runtime or daemon.
- **JSON / gzip**: schema-driven records plus portable compressed evidence.
- **Read-only diagnostics first**: the tool never performs risky repair commands, only a human following a safe runbook can do that.
- **No dashboard in v1**: the CLI and evidence model must be trustworthy before adding a GUI.
- **No invented business outcomes**: resume claims are held until verified lab and test evidence exists.

After VM acceptance, optional v1.1 may explore opt-in, rate-limited systemd-triggered capture; v2 may add a local GUI/data-access API. This is a plan, **not a feature claim**.

## Project structure

```text
bin/uir                  Bash entry point
lib/                     CLI, validation, collectors, store, comparison,
                         search, report, export, sanitizer, retention
tests/                   Bats, smoke, seeded fixtures, full integration checks
lab/setup/               Ubuntu VM and WSL instructions
lab/incidents/           12 reproduction and rollback runbooks
docs/kb/                 12 knowledge-base articles
docs/incidents/          Case-study template and honest execution tracker
docs/                    Architecture, operations, security, testing
config/                  Settings examples (not executable configuration)
examples/sanitized/       Explicitly synthetic demonstration data
Makefile                  Optional developer targets
.github/workflows/       CI definition for eventual publication
```

## Contribution, license and authenticity

The source is released under the [MIT License](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) for safety expectations. If you encounter a sensitive-data vulnerability, follow [SECURITY.md](SECURITY.md).

This project is built as a learning-focused technical portfolio artifact. It demonstrates design, engineering, testing and documentation decisions. **A successful mock incident never substitutes for genuine production support experience.** Claims in a future CV should be supported by actual reproducible test reports and VM observations.
