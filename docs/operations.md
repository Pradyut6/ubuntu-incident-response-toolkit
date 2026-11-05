# Operator handbook — complete v1 CLI journey

## Environment and safety

Use Ubuntu Server 24.04 LTS on VirtualBox. First establish console access, NAT networking, Nginx and OpenSSH, then take a `CLEAN-BASELINE` VM snapshot. WSL is fine for read-only development/testing but deliberately breaking Nginx, SSH, disk or firewall services there can affect your main workflow. Store evidence under the Linux home folder, not a Windows-mounted path.

Install dependencies:

```bash
sudo apt update
sudo apt install -y jq gzip tar coreutils iproute2 curl nginx openssh-server shellcheck shfmt bats
./bin/uir doctor
```

For files extracted from a ZIP into your project folder, set executable bit once: `chmod +x bin/uir`.

## One incident from start to finish

```bash
# In a disposable Ubuntu VM (never a production host)
./bin/uir init
./bin/uir incident create --id INC-007 --service nginx --severity high \
  --summary 'Simulated Nginx outage in isolated lab'
./bin/uir incident status --id INC-007 --value investigating
# Follow the read-only preflight and isolated fault exercise in lab/incidents/INC-007.md
./bin/uir capture --incident INC-007 --phase before --minutes 15
./bin/uir incident note --id INC-007 --kind hypothesis --text 'Hypothesis based on actual output'
# Restore the dedicated test config by following the incident's recovery step
./bin/uir capture --incident INC-007 --phase after --minutes 15
./bin/uir compare --incident INC-007
./bin/uir incident note --id INC-007 --kind root_cause --text 'Confirmed cause from recorded evidence'
./bin/uir incident note --id INC-007 --kind remediation --text 'Exact manual fix and risk'
./bin/uir incident note --id INC-007 --kind verification --text 'Observed functional test outcome'
./bin/uir incident status --id INC-007 --value resolved
./bin/uir report --incident INC-007
./bin/uir incident search --service nginx --text 'nginx'
./bin/uir export --incident INC-007 --preview
./bin/uir export --incident INC-007 --output ./INC-007-handoff.tar.gz
```

A `partial` capture is **not** an error-free success: inspect `collector_results` and decompress diagnostics with `gzip -cd ~/.local/share/ubuntu-irt/incidents/INC-007/before/diagnostics.txt.gz`. An inaccessible journal may yield empty `journal.jsonl.gz`; do not invent records. Each phase is immutable; create a distinct incident for repeat exercises rather than overwriting evidence.

## Search and notes

- `uir incident list` and `uir incident show INC-007` validate persistent records.
- `uir incident search --id INC-007 --since 2026-11-01 --severity high` combines structured filters.
- `uir incident search --text 'address already in use'` performs literal case-insensitive search against JSON metadata and captured bounded gzip files. The search string is never treated as a shell command.
- Notes use kinds `hypothesis`, `root_cause`, `remediation`, `verification`, or `customer_update`; their timestamps are UTC.

## Retention

Default: **30 days**, **500 MiB managed incident store**, **10 MiB per compressed capture**. These are best-effort local bounds; quotas are checked before publication and have documented race limitations. User controls:

```bash
./bin/uir retention status
./bin/uir retention set --days 45 --max-storage-mb 600 --capture-max-mb 8
./bin/uir retention prune --dry-run
# Only after carefully reading its plan:
./bin/uir retention prune --yes
```

Pruning removes expired incident folders and, when over the configured quota, the oldest additional folders. The tool **never automatically** deletes incident evidence or external handoff archives. Unlike snapshots, retention commands deliberately change the private incident store; read the dry-run output and preserve important archives first.

## Export verification

```bash
mkdir -p ~/uir-review
# Extract ONLY this archive that you created and whose entry list you reviewed.
tar -tzf ./INC-007-handoff.tar.gz
# Check that there are no absolute, traversal or symlink members first.
tar -xzf ./INC-007-handoff.tar.gz -C ~/uir-review
(cd ~/uir-review && sha256sum -c SHA256SUMS)
find ~/uir-review -type f -maxdepth 3 -print
```

The checksum verifies transfer integrity, **not redaction completeness**. Review `report.md`, JSON and decompressed logs for secret types not covered by regexes before making the archive public. Don't upload raw evidence to GitHub.

## Failure handling

- **Missing `jq`**: install `jq`, rerun `doctor`; metadata commands return exit code 3.
- **Partial collector / empty journal**: inspect stored JSON, confirm systemd availability, journal group membership or guest permissions; never run the whole CLI as root.
- **Unsupported service profile**: create incidents for `host`, `nginx`, `ssh` or a disposable `uir-*` unit. New profiles require code review and tests.
- **Filesystem mode error**: move the data store onto a native Linux filesystem. Never blindly `chmod -R` unrelated paths.
- **Gzip corrupted**: copy evidence to a safe private backup for analysis; the tool refuses to export it.
- **Export already exists**: provide a different safe filename; overwrite is intentionally denied.
- **Snapshot already exists**: preserve it. Use a new incident ID to repeat the exercise.
