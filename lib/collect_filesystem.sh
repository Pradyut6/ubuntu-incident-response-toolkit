#!/usr/bin/env bash
# Read-only, bounded filesystem usage observation for an explicit directory.
# No directory listing, file contents, mount operations, or raw target path stored.

uir::collect::filesystem() {
    local path="$1" json="$2" diagnostics="$3"
    local now measure='' rc=0 block blocks free avail inodes inode_free fs_type other=''
    local target_hash

    uir::validate::filesystem_path "$path" || return 2
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    target_hash="$(printf '%s' "$path" | sha256sum | cut -d' ' -f1)" || return 5
    measure="$(LC_ALL=C timeout --kill-after=1s 8s stat -f -c '%S %b %f %a %c %d %T' -- "$path" 2>/dev/null)" || rc=$?
    if ((rc == 0)); then
        read -r block blocks free avail inodes inode_free fs_type other <<<"$measure"
        if [[ -n "$other" || ! "$block" =~ ^[0-9]+$ || ! "$blocks" =~ ^[0-9]+$ ||
            ! "$free" =~ ^[0-9]+$ || ! "$avail" =~ ^[0-9]+$ ||
            ! "$inodes" =~ ^[0-9]+$ || ! "$inode_free" =~ ^[0-9]+$ ||
            ! "$fs_type" =~ ^[a-zA-Z0-9_./-]+$ ]] ||
            ((block == 0 || blocks == 0 || free > blocks || avail > blocks || inode_free > inodes)); then
            rc=5
        fi
    fi
    if ((rc != 0)); then
        jq -n --arg time "$now" --arg hash "$target_hash" --argjson exitcode "$rc" \
            '{checked_at:$time,target_sha256:$hash,scope:"selected_directory_filesystem",
            status:"collector_error",stat_exit:$exitcode,
            fs_type:null,size_bytes:null,used_bytes:null,available_bytes:null,
            used_percent:null,inodes_total:null,inodes_available:null,inodes_used_percent:null}' >"$json" || return 5
        printf '[Filesystem collection unavailable, stat_exit=%s]\n' "$rc" >>"$diagnostics"
        return 1
    fi

    jq -n --arg time "$now" --arg hash "$target_hash" --arg type "$fs_type" \
        --argjson block "$block" --argjson blocks "$blocks" \
        --argjson free "$free" --argjson avail "$avail" \
        --argjson inodes "$inodes" --argjson inode_free "$inode_free" \
        '{checked_at:$time,target_sha256:$hash,scope:"selected_directory_filesystem",
        status:"observed",stat_exit:0,fs_type:$type,
        size_bytes:($block*$blocks),used_bytes:($block*($blocks-$free)),
        available_bytes:($block*$avail),
        used_percent:((10000*(($blocks-$free)/$blocks)|floor)/100),
        inodes_total:(if $inodes>0 then $inodes else null end),
        inodes_available:(if $inodes>0 then $inode_free else null end),
        inodes_used_percent:(if $inodes>0 then ((10000*(($inodes-$inode_free)/$inodes)|floor)/100) else null end)}' \
        >"$json" || return 5
    printf '[Filesystem status=observed type=%s size_blocks=%s available_blocks=%s inode_total=%s inode_free=%s]\n' \
        "$fs_type" "$blocks" "$avail" "$inodes" "$inode_free" >>"$diagnostics"
}
