#!/usr/bin/env bash
# Deterministic seeded-string test; fixture tokens are fabricated.
set -euo pipefail
project="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "$project/lib/sanitize.sh"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
cat >"$work/raw" <<'RAW'
Authorization: Bearer demo-token-very-secret
password=demo_password_123
{"token":"jsonTokenValue999"}
Token: demo123token
alice@example.com
AKIA1234567890123456
192.168.0.32
/home/alice/.ssh/id_rsa
-----BEGIN OPENSSH PRIVATE KEY-----
PRIVATE_KEY_MATERIAL_SUPER_SECRET
-----END OPENSSH PRIVATE KEY-----
RAW
uir::sanitize::public <"$work/raw" >"$work/redacted"
for value in demo-token-very-secret demo_password_123 demo123token jsonTokenValue999 PRIVATE_KEY_MATERIAL_SUPER_SECRET alice@example.com AKIA1234567890123456 192.168.0.32 /home/alice/.ssh; do
    if grep -Fq "$value" "$work/redacted"; then
        echo "FAIL: unredacted fixture $value" >&2
        exit 1
    fi
done
for expected in '[REDACTED]' '[REDACTED_EMAIL]' '[REDACTED_AWS_KEY]' '[REDACTED_IPv4]' '[REDACTED_PRIVATE_KEY_BLOCK]'; do
    grep -Fq "$expected" "$work/redacted" || {
        echo "FAIL: missing marker $expected" >&2
        exit 1
    }
done
printf 'PASS: nine seeded values removed; five replacement classes identified.\n'
