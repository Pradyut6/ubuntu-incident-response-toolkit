# Contributing safely

1. Open an issue with expected versus actual behavior, Ubuntu/WSL version and a **synthetic, sanitized** reproduction. Never include raw journal exports, SSH keys, credentials, live organization data, incident database copies or VM images.
2. Develop in a branch. Prefer small Bash modules, quoted arguments, validated inputs, explicit timeout boundaries and **no `eval` or automatic `sudo`**.
3. Add deterministic fixture tests for both positive and negative paths. Non-disruptive WSL 2 integration is supported; native Ubuntu/VM verification must be described separately and only when actually performed.
4. Run `bash tests/run-all.sh`, confirm exit `0`, and examine the log for actual ShellCheck/shfmt/Bats `SKIP` lines. Do not assert a check ran if the tool was missing.
5. Record behavior changes, uncertainty and limitations in tests and docs; never claim a synthetic incident was a customer outage.
6. Review `git diff --cached`, generated files, private paths, usernames and release examples before every push. Run the [release checklist](docs/release-checklist.md).

The project is a learning-focused incident-triage toolkit. It does **not** auto-remediate production systems.
