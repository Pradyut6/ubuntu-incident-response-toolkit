# Development and safe incident exercises on WSL 2

The toolkit was developed and tested using **Ubuntu 24.04 under WSL 2**. The training exercises used purpose-built local services, capped tmpfs mounts, short bounded workloads and synthetic fixtures. **No Oracle VirtualBox VM acceptance was performed.** This page replaces earlier VirtualBox-first operational advice; historical plans remain in `docs/planning/`.

## Repository and private data

Work from the **existing repository**, whether it resides under a Windows-mounted development directory or a Linux home project directory. Do not create an extra version directory just to run tests. For a future migration, adjust `<windows-user>` to your own user name:

```bash
# Optional future migration, NOT required for WSL validation:
# mkdir -p "$HOME/projects"
# cp -a "/mnt/c/Users/<windows-user>/Downloads/ubuntu-incident-response-toolkit" "$HOME/projects/"
# cd "$HOME/projects/ubuntu-incident-response-toolkit"
```

The **private runtime data is different from the source checkout**. It must be stored in the Linux home filesystem:

```bash
printf 'XDG_DATA_HOME=%s\n' "${XDG_DATA_HOME:-<unset>}"
./bin/uir init
# Default: ~/.local/share/ubuntu-irt
```

Avoid pointing `XDG_DATA_HOME` at `/mnt/c`: POSIX permissions and ownership can behave differently on DrvFS. Do not add real incident evidence to the Git repository.

## Safe validation

```bash
./bin/uir doctor
bash tests/run-all.sh
./bin/uir incident list
```

The automated tests use disposable state and fixtures. For manual examples, only operate on uniquely named `uir-training-*` systemd units or isolated localhost servers, and confirm ownership and cleanup preconditions before removing resources. Captures themselves are read-only; **setup/cleanup scripts are not** and require careful review before execution.

- **Do not** alter the primary WSL firewall, DNS resolver, APT database or filesystem capacity to simulate an incident.
- Use synthetic APT-lock and firewall-denial log lines rather than causing real system-wide failures.
- For disk-full demonstrations, use a separately mounted, tiny tmpfs; verify the exact mount and unmount it safely afterward.
- Preserve before/after incident snapshots, checksum results and explicit cleanup evidence outside the repository. The case-study tracker records what was actually observed.
- A permission-limited unprivileged Nginx test should remain a `partial` capture; check separately with `sudo nginx -t` if justified, not `sudo ./bin/uir`.

## Scope of the evidence

On November 14, 2026 the operator's WSL 2 regression suite reached **13/13 stages** with exit `0`. These are local test results, **not native Ubuntu/VirtualBox certification or evidence of production outages**. See [`docs/testing.md`](../../docs/testing.md), [`docs/incidents/STATUS.md`](../../docs/incidents/STATUS.md) and the [release checklist](../../docs/release-checklist.md).
