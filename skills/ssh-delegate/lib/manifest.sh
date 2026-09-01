#!/bin/sh
# lib/manifest.sh — read/write the delegation manifest (SSOT of trust).
#
# Manifest format is documented in references/manifest-schema.md. The
# canonical store is `~/.ssh/delegations.yml` (override: $DEVX_SSH_MANIFEST).
#
# ENGINE NOTE (issue #877): the issue named `yq` as the parser. yq is treated
# as an OPTIONAL validator (see `doctor`); the authoritative read/write path
# below is dependency-free awk so the skill runs standalone on a bare machine
# — an explicit acceptance requirement ("standalone 동작"). All writes go
# through manifest_save_tsv which re-emits canonical YAML, so a round-trip is
# lossless for the documented schema.
#
# Internal interchange is a fixed 11-column TAB-separated row:
#   alias user host port identity_file note expires \
#   installed_at last_verified_at fingerprint_sha256 revoked
#
# Sourced — POSIX sh only.

manifest_path() {
    printf '%s\n' "${DEVX_SSH_MANIFEST:-$HOME/.ssh/delegations.yml}"
}

manifest_field_col() {
    case "$1" in
    alias) echo 1 ;; user) echo 2 ;; host) echo 3 ;; port) echo 4 ;;
    identity_file) echo 5 ;; note) echo 6 ;; expires) echo 7 ;;
    installed_at) echo 8 ;; last_verified_at) echo 9 ;;
    fingerprint_sha256) echo 10 ;; revoked) echo 11 ;;
    *) return 1 ;;
    esac
}

# Create an empty skeleton manifest with mode 0600 if absent.
manifest_ensure() {
    file="$(manifest_path)"
    if [ ! -f "$file" ]; then
        dir="$(dirname "$file")"
        [ -d "$dir" ] || mkdir -p "$dir"
        printf 'version: 1\ndefaults:\n  identity_file: ~/.ssh/id_ed25519\n  port: 22\n  strict_host_key_checking: yes\nentries:\n' >"$file"
        chmod 600 "$file"
    fi
}

# Read a value from the defaults: block.
manifest_default() {
    file="$(manifest_path)"
    [ -f "$file" ] || return 1
    awk -v want="$1" '
        /^[^ ]/ { in_d = ($0 ~ /^defaults:/) ? 1 : 0; next }
        in_d==1 {
            line=$0; sub(/^[ ]+/, "", line)
            if (line ~ /^[A-Za-z0-9_]+:/) {
                k=line; sub(/:.*/, "", k)
                v=line; sub(/^[A-Za-z0-9_]+:[ ]*/, "", v)
                if (k==want) { gsub(/^"|"$/, "", v); print v; exit }
            }
        }' "$file"
}

# Parse entries: into the 11-column TSV interchange (one row per entry).
manifest_to_tsv() {
    file="$(manifest_path)"
    [ -f "$file" ] || return 0
    awk '
        function strip(v) {
            sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
            if (v ~ /^".*"$/) v = substr(v, 2, length(v)-2)
            else if (v ~ /^'\''.*'\''$/) v = substr(v, 2, length(v)-2)
            return v
        }
        function flush() {
            if (have) printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                f["alias"], f["user"], f["host"], f["port"], f["identity_file"],
                f["note"], f["expires"], f["installed_at"], f["last_verified_at"],
                f["fingerprint_sha256"], f["revoked"]
            delete f; have=0
        }
        BEGIN { in_e=0; have=0 }
        /^[^ ]/ { if ($0 ~ /^entries:/) { in_e=1 } else { if (in_e) flush(); in_e=0 } next }
        in_e==1 {
            line=$0
            is_new = (line ~ /^[ ]+-[ ]+/)
            sub(/^[ ]+/, "", line)
            if (is_new) { flush(); have=1; sub(/^-[ ]+/, "", line) }
            if (have && line ~ /^[A-Za-z0-9_]+:/) {
                k=line; sub(/:.*/, "", k)
                v=line; sub(/^[A-Za-z0-9_]+:[ ]*/, "", v)
                f[k]=strip(v)
            }
        }
        END { flush() }
    ' "$file"
}

# Re-emit canonical YAML from TSV rows on stdin. Defaults are preserved from
# the existing manifest (or fall back to built-ins).
manifest_emit() {
    idf="$(manifest_default identity_file 2>/dev/null)"
    # shellcheck disable=SC2088  # literal ~ kept verbatim in the YAML default
    [ -n "$idf" ] || idf='~/.ssh/id_ed25519'
    prt="$(manifest_default port 2>/dev/null)"
    [ -n "$prt" ] || prt='22'
    shk="$(manifest_default strict_host_key_checking 2>/dev/null)"
    [ -n "$shk" ] || shk='yes'
    printf 'version: 1\ndefaults:\n'
    printf '  identity_file: %s\n' "$idf"
    printf '  port: %s\n' "$prt"
    printf '  strict_host_key_checking: %s\n' "$shk"
    printf 'entries:\n'
    # awk (not `read`) parses the TSV: a tab IFS in `read` is whitespace and
    # collapses empty columns, but awk -F'\t' preserves them.
    awk -F'\t' '
        $1=="" { next }
        {
            printf "  - alias: %s\n", $1
            printf "    user: %s\n", $2
            printf "    host: %s\n", $3
            if ($4 != "")  printf "    port: %s\n", $4
            if ($5 != "")  printf "    identity_file: %s\n", $5
            if ($6 != "")  printf "    note: \"%s\"\n", $6
            if ($7 != "")  printf "    expires: %s\n", $7
            if ($8 != "")  printf "    installed_at: %s\n", $8
            if ($9 != "")  printf "    last_verified_at: %s\n", $9
            if ($10 != "") printf "    fingerprint_sha256: %s\n", $10
            printf "    revoked: %s\n", ($11=="" ? "false" : $11)
        }'
}

# Atomically replace the manifest from TSV rows on stdin (mode 0600).
manifest_save_tsv() {
    file="$(manifest_path)"
    dir="$(dirname "$file")"
    [ -d "$dir" ] || mkdir -p "$dir"
    tmp="${file}.tmp.$$"
    if manifest_emit >"$tmp"; then
        chmod 600 "$tmp"
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}

manifest_aliases() { manifest_to_tsv | awk -F'\t' 'NF{print $1}'; }

manifest_has() {
    manifest_to_tsv | awk -F'\t' -v a="$1" '$1==a{f=1} END{exit !f}'
}

manifest_get() {
    col="$(manifest_field_col "$2")" || return 1
    manifest_to_tsv | awk -F'\t' -v a="$1" -v c="$col" '$1==a{print $c; exit}'
}

# Effective value: per-entry override ($2) falls back to defaults ($3).
manifest_eff() {
    v="$(manifest_get "$1" "$2")"
    if [ -n "$v" ]; then printf '%s\n' "$v"; else manifest_default "$3"; fi
}

manifest_set_field() {
    col="$(manifest_field_col "$2")" || return 1
    manifest_to_tsv |
        awk -F'\t' -v OFS='\t' -v a="$1" -v c="$col" -v v="$3" '$1==a{$c=v} {print}' |
        manifest_save_tsv
}

# Insert a new entry, or update user/host/note/expires of an existing one.
manifest_upsert() {
    al="$1"
    us="$2"
    ho="$3"
    no="$4"
    ex="$5"
    if manifest_has "$al"; then
        # Single awk pass + one atomic write (was 4 read-write cycles).
        manifest_to_tsv |
            awk -F'\t' -v OFS='\t' -v a="$al" -v us="$us" -v ho="$ho" -v no="$no" -v ex="$ex" '
                $1==a {
                    $2=us
                    $3=ho
                    if (no != "") $6=no
                    if (ex != "") $7=ex
                }
                { print }' |
            manifest_save_tsv
        return 0
    fi
    {
        manifest_to_tsv
        # 11 columns; cols 4,5 (port,identity_file) and 8,9,10 (timestamps,
        # fingerprint) start empty — populated later by install/verify.
        printf '%s\t%s\t%s\t\t\t%s\t%s\t\t\t\tfalse\n' "$al" "$us" "$ho" "$no" "$ex"
    } | manifest_save_tsv
}
