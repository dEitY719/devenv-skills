#!/usr/bin/env bash
# Repo self-checks, discovered and run by the reusable skill-check workflow
# (`tests/*.sh`, harness-skills). The list below is explicit -- probing every
# lib script with an unknown flag is not safe, these scripts install keys and
# move files -- but a missing entry must not be a silent skip, so the guard
# below fails when a script advertises --self-test and is not listed.

set -euo pipefail
cd "$(dirname "$0")/.."

CHECKS=(
    skills/mise-migrate/lib/detect_project.sh
    skills/mise-migrate/lib/stale_scan.sh
    skills/symlink-manager/lib/symlink_migrate.sh
)

# Every entry must be a tracked file, and CI must say so by name rather than
# by whatever `sh` prints when it cannot open one. CHECKS reaches outside the
# skill whose change added it, so an entry can go stale from a rename made
# elsewhere in the repo.
missing=0
for c in "${CHECKS[@]}"; do
    git ls-files --error-unmatch "$c" >/dev/null 2>&1 && continue
    echo "FAIL  $c is listed in tests/run.sh but is not a tracked file"
    missing=1
done

while IFS= read -r s; do
    # Matches the case label in any spelling a script might use for it
    # (`--self-test)`, `--self-test|--selftest)`), not one exact string.
    grep -qE -- '^[[:space:]]*(-[^)]*\|)*--self-test(\|[^)]*)?\)' "$s" || continue
    listed=0
    for c in "${CHECKS[@]}"; do [ "$c" = "$s" ] && listed=1; done
    if [ "$listed" -eq 0 ]; then
        echo "FAIL  $s supports --self-test but is not listed in tests/run.sh"
        missing=1
    fi
done < <(git ls-files 'skills/*/lib/*.sh')
[ "$missing" -eq 0 ] || exit 1

for s in "${CHECKS[@]}"; do
    echo "note  $s --self-test"
    sh "$s" --self-test
done

echo "ok    ${#CHECKS[@]} self-test(s) passed"
