# M1 — Isolated Ubuntu 24.04 LTS VirtualBox baseline

**State: USER-SIDE VALIDATION REQUIRED.** This guide does not mean the VM has been created, inspected, or restored.

## 1. Create the VM on your host

1. Obtain the official **Ubuntu Server 24.04 LTS amd64 ISO** from https://releases.ubuntu.com/24.04/ and install Oracle VirtualBox from https://www.virtualbox.org/ (on Windows, check hardware virtualization and any Hyper-V conflicts first).
2. Create a VM named `ubuntu-irt-lab`: **Linux / Ubuntu (64-bit)**, **2 vCPU, 2048 MB RAM, 25 GB dynamically allocated disk**. If your host becomes sluggish, reduce concurrent applications and reconsider allocation; do not starve the host OS.
3. Keep Network Adapter 1 set to **NAT**. Do not select bridged mode for fault-injection exercises. Do not expose ports publicly.
4. Mount the ISO and install Ubuntu Server with a non-root user. Optional: install OpenSSH Server, but **retain access to the VirtualBox console**. Let the installer update only from official Ubuntu sources.
5. Remove the virtual installer ISO when asked, reboot, and log in through the guest console.

Useful official reference: https://ubuntu.com/server/docs/tutorial/basic-installation/

## 2. Install tools inside the guest

Run **inside the Ubuntu VM**, NOT on the Windows host:

```bash
sudo apt update
sudo apt install -y nginx openssh-server curl jq iproute2 \
  shellcheck shfmt bats git gzip tar coreutils
```

On minimal installs, `universe` must be enabled for some developer packages. If apt cannot locate `bats` or `shfmt`, verify official Ubuntu repository components rather than adding untrusted third-party PPAs.

Check:

```bash
cat /etc/os-release
systemctl status nginx --no-pager
systemctl status ssh.socket --no-pager
systemctl status ssh.service --no-pager
curl -fsSI http://127.0.0.1/
jq --version
shellcheck --version
shfmt --version
bats --version
```

*Note:* Ubuntu 24.04 generally uses systemd socket activation for OpenSSH. The status of `ssh.service` alone is not always conclusive: inspect `ssh.socket` and actual connectivity. For the initial baseline, it is okay if SSH has not been enabled, but record that fact.

## 3. Verify basic host health

```bash
uname -a
free -h
df -h /
ip -brief address
ip route
getent hosts ubuntu.com
systemctl is-active nginx
curl -fsSI http://127.0.0.1/
```

Do not begin fault injection if Nginx or guest console access is not working.

## 4. Capture a CLEAN-BASELINE VM snapshot

1. Shut the guest down cleanly using `sudo poweroff`.
2. In VirtualBox Manager select the VM → **Snapshots** → **Take**.
3. Name it **CLEAN-BASELINE**, and note Ubuntu version, installed packages, and guest networking mode in the description.
4. To **test restore**, start the VM, create a harmless disposable marker (`touch ~/uir-snapshot-test`), shut it down, restore CLEAN-BASELINE using VirtualBox Manager, and start it again. The marker must be gone, while Nginx and console login must still work.
5. This restore intentionally discards guest changes since the snapshot. **Do not put unbacked-up work inside the VM** when rehearsing a restore.

## 5. M1 acceptance checks

- [ ] `cat /etc/os-release` shows `ID=ubuntu`, `VERSION_ID="24.04"`.
- [ ] VM uses NAT; console login succeeds.
- [ ] `nginx` reports active and `curl -fsSI http://127.0.0.1/` returns an HTTP 200 response (or a clearly justified alternative successful status).
- [ ] Package manager works and test tools are installed.
- [ ] `CLEAN-BASELINE` snapshot exists **and restore was tested**.
- [ ] Guest resource usage is acceptable on the host.

**Stop here if any check fails.** Never begin breaking services before baseline and recovery have been verified.

## 6. Transfer the starter project from Windows to the Ubuntu VM (optional SSH method)

Once your CLEAN-BASELINE snapshot has been tested, leave networking in **NAT** mode and use an SSH loopback-only port forward. In the VM's VirtualBox settings: **Network → Adapter 1 (NAT) → Advanced → Port Forwarding**. Add a rule with Protocol `TCP`, Host IP `127.0.0.1`, Host Port `2222`, Guest IP blank, Guest Port `22`. Do not forward to `0.0.0.0` or use bridged networking.

Inside the VM, verify the SSH socket is available:

```bash
sudo systemctl enable --now ssh.socket
sudo systemctl status ssh.socket --no-pager
```

From **Windows PowerShell on your host**, after downloading the project zip to your Downloads folder, substitute your guest login for `vmuser`:

```powershell
scp -P 2222 "$env:USERPROFILE\Downloads\ubuntu-incident-response-toolkit-starter-m2.zip" vmuser@127.0.0.1:~/
```

Inside the Ubuntu guest:

```bash
sudo apt install -y unzip
unzip -q ~/ubuntu-incident-response-toolkit-starter-m2.zip -d ~/
cd ~/ubuntu-incident-response-toolkit
chmod +x bin/uir tests/smoke.sh
./bin/uir doctor
bash tests/smoke.sh
```

To verify the SSH tunnel first from Windows, run `ssh -p 2222 vmuser@127.0.0.1`. If it fails, verify NAT forwarding, the guest's `ssh.socket`, and that you can still log in at the VM console. SSH port forwarding is **optional**; it is not a prerequisite for running the toolkit in the guest console.
