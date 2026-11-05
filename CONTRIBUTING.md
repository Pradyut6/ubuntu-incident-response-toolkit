# Contributing safely

1. Open an issue describing the expected behavior, affected Ubuntu version and a sanitized minimal reproduction. **Never include raw journal exports, SSH keys, credentials, live customer/school data or VM disks.**
2. Make changes in a local branch. Prefer narrow Bash modules with clearly validated inputs and no `eval`, arbitrary shell or automatic `sudo`.
3. Add a deterministic fixture test for failures and an isolated VM smoke check for service-specific behavior.
4. Run `bash tests/run-all.sh`; do not claim passing gates you skipped. Do not run fault injection on a work, WSL or production host.
5. Write down the security limitation and any operator-visible behavior change. Keep incident samples explicitly labeled synthetic or verified.
6. Review the Git diff for secrets and machine-specific paths before committing.

This project is designed for learning and review, not for automatically repairing production systems.
