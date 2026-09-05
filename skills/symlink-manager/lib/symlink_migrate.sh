#!/bin/sh
# symlink_migrate.sh — Phase 1 (+ optional Phase 4) of devenv:symlink-manager.
#
# Moves one config file into the dotfiles repo and links it back. It is the
# single artifact that both makes and keeps SKILL.md's promise (issue #5):
# the backup is created BEFORE anything touches the original, the copy is
# compared byte-for-byte with `cmp -s` (not `cat`) before the original is
# removed, and any Phase 1 failure restores the original from that backup and
# exits non-zero. Prose in references/ can drift from a command list; a script
# that rolls itself back cannot.
#
# Usage:
#   symlink_migrate.sh <target_file> <category> [--commit]
#   symlink_migrate.sh --self-test
#
# <category> is one of claude | app | config | env. The dotfiles root is
# $DOTFILES_ROOT (default ~/dotfiles). Phase 4 (--commit) failures do NOT roll
# back: the link is already good at that point, and the backup is still there.
#
# Called explicitly, never sourced. POSIX sh only.

set -u

DOTFILES="${DOTFILES_ROOT:-$HOME/dotfiles}"

usage() {
    cat <<'EOF'
devenv:symlink-manager — Phase 1 file migration with backup + rollback

Usage:
  symlink_migrate.sh <target_file> <category> [--commit]
  symlink_migrate.sh --self-test

  <category>   claude | app | config | env
  --commit     also run Phase 4 (git add + commit in the dotfiles repo)

Order of operations: <target_file>.backup -> copy to dotfiles -> cmp -s ->
rm original -> ln -s -> verify. Any failure before the link is verified
restores the original from the backup and exits non-zero.
EOF
}

fail() {
    printf '[FAIL] devenv:symlink-manager phase=%s reason=%s\n' "$1" "$2" >&2
    exit 1
}

# rollback <phase> <reason> — put the original back, then fail.
rollback() {
    if [ "$DEST_PREEXISTING" = no ] && [ -e "$DEST" ]; then
        rm -f "$DEST"
    fi
    if [ -e "$BACKUP" ]; then
        if [ -L "$TARGET" ]; then
            rm -f "$TARGET"
        fi
        mv "$BACKUP" "$TARGET" ||
            fail "$1" "$2; ROLLBACK FAILED - original is at $BACKUP"
    fi
    fail "$1" "$2 (rolled back)"
}

# migrate <target_file> <category> <yes|no commit>
migrate() {
    TARGET="$1"
    CATEGORY="$2"
    DO_COMMIT="$3"

    case "$CATEGORY" in
        claude | app | config | env) ;;
        *) fail 0 "unknown category '$CATEGORY' (claude|app|config|env)" ;;
    esac
    [ -e "$TARGET" ] || fail 0 "target not found: $TARGET"

    FILENAME=$(basename "$TARGET")
    # Resolves and existence-checks in one step, and makes DEST absolute so the
    # symlink is valid from any cwd.
    DEST_DIR=$(CDPATH='' cd -- "$DOTFILES/bash/$CATEGORY" 2>/dev/null && pwd) ||
        fail 1 "category dir missing: $DOTFILES/bash/$CATEGORY"
    DEST="$DEST_DIR/$FILENAME"
    BACKUP="$TARGET.backup"
    DEST_PREEXISTING=no
    [ -e "$DEST" ] && DEST_PREEXISTING=yes

    if [ -L "$TARGET" ]; then
        # Already migrated — Phase 4 re-invokes this script with --commit, and
        # a re-run must be a no-op rather than a second migration.
        [ "$(readlink "$TARGET")" = "$DEST" ] ||
            fail 0 "target links to $(readlink "$TARGET"), not $DEST"
        cmp -s "$TARGET" "$DEST" || fail 0 "symlink does not read back $DEST"
    else
        [ -f "$TARGET" ] || fail 0 "target is not a regular file: $TARGET"
        [ -w "$DEST_DIR" ] || fail 1 "category dir not writable: $DEST_DIR"
        # An existing .backup is someone else's safety net. Never clobber it.
        if [ -e "$BACKUP" ]; then
            fail 1 "backup already exists: $BACKUP (move it aside first)"
        fi

        # 1. Backup first — before anything can touch the original.
        cp -p "$TARGET" "$BACKUP" || fail 1 "cannot create backup: $BACKUP"
        cmp -s "$TARGET" "$BACKUP" || rollback 1 "backup is not byte-identical"

        # 2. Copy into dotfiles, then actually compare it. `cat` proves nothing.
        cp "$TARGET" "$DEST" || rollback 1 "copy to $DEST failed"
        cmp -s "$TARGET" "$DEST" || rollback 1 "copy differs from source: $DEST"

        # 3. Only now is removing the original safe.
        rm -f "$TARGET" || rollback 1 "cannot remove original: $TARGET"
        ln -s "$DEST" "$TARGET" || rollback 1 "cannot create symlink: $TARGET"

        # 4. Verify the link resolves and reads back identical.
        [ -L "$TARGET" ] || rollback 1 "not a symlink after ln: $TARGET"
        [ -r "$TARGET" ] || rollback 1 "symlink does not resolve: $TARGET"
        cmp -s "$TARGET" "$DEST" || rollback 1 "link content differs from $DEST"
    fi

    SHA=none
    if [ "$DO_COMMIT" = yes ]; then
        # Anything the caller already staged (e.g. bash/app/<app>.bash) rides
        # along in the same commit, matching the Phase 4 command list.
        git -C "$DOTFILES" add -- "bash/$CATEGORY/$FILENAME" ||
            fail 4 "git add failed in $DOTFILES"
        git -C "$DOTFILES" commit -q \
            -m "feat: manage $FILENAME via dotfiles with symbolic link" ||
            fail 4 "git commit failed in $DOTFILES"
        SHA=$(git -C "$DOTFILES" rev-parse --short HEAD)
    fi

    [ -e "$BACKUP" ] || BACKUP=none
    printf '[OK] devenv:symlink-manager target=%s category=%s links=1 commit=%s backup=%s\n' \
        "$TARGET" "$CATEGORY" "$SHA" "$BACKUP"
}

# The two assertions issue #5 names: the backup exists at the moment of
# deletion, and the rollback actually fires. Run: symlink_migrate.sh --self-test
self_test() {
    st_tmp=$(mktemp -d) || { printf 'mktemp failed\n' >&2; return 1; }
    trap 'rm -rf "$st_tmp"' EXIT INT TERM
    DOTFILES="$st_tmp/dotfiles"
    mkdir -p "$DOTFILES/bash/env" || return 1
    st_rc=0

    st_check() {
        if [ "$1" = ok ]; then
            printf '  ok    %s\n' "$2"
        else
            printf '  FAIL  %s\n' "$2"
            st_rc=1
        fi
    }
    st_assert() {
        if eval "$1"; then st_check ok "$2"; else st_check no "$2"; fi
    }

    printf 'case 1: happy path leaves a byte-identical .backup\n'
    printf 'sentinel\n' >"$st_tmp/sm.conf"
    printf 'sentinel\n' >"$st_tmp/expected"
    ( migrate "$st_tmp/sm.conf" env no ) >"$st_tmp/out" 2>&1
    st_assert "[ $? -eq 0 ]" "migration exits 0"
    st_assert "cmp -s '$st_tmp/sm.conf.backup' '$st_tmp/expected'" \
        "backup is byte-identical to the original"
    st_assert "[ -L '$st_tmp/sm.conf' ]" "target is now a symlink"
    st_assert "cmp -s '$st_tmp/sm.conf' '$DOTFILES/bash/env/sm.conf'" \
        "link reads back the migrated content"
    ( migrate "$st_tmp/sm.conf" env no ) >>"$st_tmp/out" 2>&1
    st_assert "[ $? -eq 0 ]" "re-run on an already-linked target is a no-op"

    printf 'case 2: induced failure rolls back, original survives\n'
    rm -f "$st_tmp/sm.conf" "$st_tmp/sm.conf.backup"
    printf 'sentinel\n' >"$st_tmp/sm2.conf"
    # Destination is a directory, so the copy cannot verify. Root-proof, unlike
    # chmod a-w, which root ignores.
    mkdir -p "$DOTFILES/bash/env/sm2.conf"
    ( migrate "$st_tmp/sm2.conf" env no ) >"$st_tmp/out2" 2>&1
    st_assert "[ $? -ne 0 ]" "migration reports failure"
    st_assert "[ -f '$st_tmp/sm2.conf' ]" "original still exists"
    st_assert "[ ! -L '$st_tmp/sm2.conf' ]" "original is not a dangling link"
    st_assert "cmp -s '$st_tmp/sm2.conf' '$st_tmp/expected'" \
        "original content is intact"
    st_assert "[ ! -e '$st_tmp/sm2.conf.backup' ]" \
        "backup consumed by the restore"

    if [ "$st_rc" -eq 0 ]; then
        printf '[OK] symlink_migrate.sh self-test\n'
    else
        printf '[FAIL] symlink_migrate.sh self-test\n' >&2
        printf -- '--- case 1 output ---\n' >&2
        cat "$st_tmp/out" >&2
        printf -- '--- case 2 output ---\n' >&2
        cat "$st_tmp/out2" >&2
    fi
    return "$st_rc"
}

case "${1:-}" in
    --self-test)
        self_test
        exit "$?"
        ;;
    -h | --help | help | '')
        usage
        exit 2
        ;;
esac

[ -n "${2:-}" ] || { usage; exit 2; }
COMMIT=no
case "${3:-}" in
    '') ;;
    --commit) COMMIT=yes ;;
    *) fail 0 "unknown option: $3" ;;
esac

migrate "$1" "$2" "$COMMIT"
