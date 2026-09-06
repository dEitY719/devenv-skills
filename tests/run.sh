#!/usr/bin/env bash
# Repo self-checks, discovered and run by the reusable skill-check workflow
# (`tests/*.sh`, harness-skills). One line per script that ships its own
# --self-test -- the assertions live next to the code they cover, not here.

set -euo pipefail
cd "$(dirname "$0")/.."

for s in skills/mise-migrate/lib/detect_project.sh \
         skills/mise-migrate/lib/stale_scan.sh \
         skills/symlink-manager/lib/symlink_migrate.sh; do
    echo "note  $s --self-test"
    sh "$s" --self-test
done

echo "ok    all self-tests passed"
