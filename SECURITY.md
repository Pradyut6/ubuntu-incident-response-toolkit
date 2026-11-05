# Reporting a security issue

Do not post a live secret or unredacted diagnostic bundle to a public issue. Before publication, communicate the issue privately with the project maintainer. After a GitHub repository is created, use its private vulnerability-reporting feature if enabled. No maintainer email is advertised in this development package.

The current implementation is a local training aid, not a security-audited forensics or SIEM system. See [docs/security.md](docs/security.md) for limitations. Report suspected path traversal, unredacted sensitive fixtures, unsafe deletion, injection or unexpected external network access with a minimal **synthetic** test case.
