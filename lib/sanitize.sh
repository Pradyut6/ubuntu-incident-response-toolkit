#!/usr/bin/env bash
# Conservative best-effort redaction. Human review remains mandatory before sharing.
# Process each line as DATA; never execute log text.
uir::sanitize::local() {
    sed -E '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\[REDACTED_PRIVATE_KEY_BLOCK]' | sed -E \
        -e 's/([Aa]uthorization[[:space:]]*:[[:space:]]*[Bb]earer[[:space:]]+)[^[:space:]"\\,}]+/\1[REDACTED]/g' \
        -e 's/([Pp]assword|[Pp]asswd|[Tt]oken|[Aa]pi[_-]?[Kk]ey|[Cc]lient[_-]?[Ss]ecret)("?[[:space:]]*[:=][[:space:]]*"?)[^[:space:]",}]+/\1\2[REDACTED]/g' \
        -e 's/AKIA[[:upper:][:digit:]]{16}/[REDACTED_AWS_KEY]/g' \
        -e 's/(-----BEGIN ([A-Z ]+)PRIVATE KEY-----).*/[REDACTED_PRIVATE_KEY_BEGIN]/g' \
        -e 's/(-----END ([A-Z ]+)PRIVATE KEY-----).*/[REDACTED_PRIVATE_KEY_END]/g'
}

uir::sanitize::public() {
    uir::sanitize::local | sed -E \
        -e 's/[[:alnum:]_.+%-]+@[[:alnum:].-]+\.[A-Za-z]{2,}/[REDACTED_EMAIL]/g' \
        -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/[REDACTED_IPv4]/g' \
        -e 's@/home/[A-Za-z0-9._-]+@/home/[REDACTED_USER]@g'
}

uir::sanitize::public_file() {
    local source="$1" dest="$2"
    uir::sanitize::public <"$source" >"$dest"
}
