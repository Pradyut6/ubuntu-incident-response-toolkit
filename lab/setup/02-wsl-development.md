# Working on the toolkit in WSL — developer notes

The screenshot-based development environment is **Ubuntu 24.04 running under WSL** with the repository at `/mnt/c/Users/.../Downloads/ubuntu-incident-response-toolkit`. The successful smoke/Bats tests validate the initial CLI, but they do **not** validate VirtualBox isolation or the full Ubuntu server incident lab.

## Recommended safe arrangement

Use WSL for normal Bash development, static analysis, metadata testing and non-disruptive collectors. Keep a separate **Ubuntu Server 24.04 VirtualBox VM** for reproducing Nginx, SSH, firewall, network or disk failures. Create a clean VM snapshot before all intentional faults.

Prefer keeping the Git working tree on a Linux filesystem:

```bash
mkdir -p ~/projects
cp -a /mnt/c/Users/DSC/Downloads/ubuntu-incident-response-toolkit ~/projects/
cd ~/projects/ubuntu-incident-response-toolkit
```

The path above follows the shared screenshot; **adjust the Windows username/location if your directory differs**. Working in `~/projects` typically yields better Linux metadata/permissions and I/O behavior than working under `/mnt/c`.

The default incident store is already in the Linux home directory:

```bash
printf 'XDG_DATA_HOME=%s\n' "${XDG_DATA_HOME:-<not set>}"
./bin/uir init
```

If `XDG_DATA_HOME` is unset, the store is `~/.local/share/ubuntu-irt`. **Do not set it to `/mnt/c/...`**: Windows-mounted permission semantics may not provide reliable `0700`/`0600` guarantees. The toolkit refuses nonprivate modes when it can detect them, but permission displays alone do not prove secure Windows ACLs.

## Read-only checks

```bash
./bin/uir doctor
bash tests/smoke.sh
bash tests/integration/m3-store.sh
bats tests/unit
```

A WSL warning from `doctor` is deliberate. A successful `journalctl` invocation alone does not prove a full native Ubuntu server logging environment. Test systemd journal visibility and service-specific collection later in the isolated VirtualBox guest.

**Do not execute future incident fault-injection scripts under WSL.** They may affect WSL networking, distro availability or other workloads on the development PC.
