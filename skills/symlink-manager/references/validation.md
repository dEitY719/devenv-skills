# Validation — checklists for Phase 5

## Phase 5 Checklist

Verify ALL before completion:

- [ ] Symbolic link exists and points to correct source
- [ ] Source file readable via symbolic link
- [ ] `<app>_init` function works correctly
- [ ] `<app>_edit_<config>` function works (if implemented)
- [ ] Help function shows new commands
- [ ] Files staged in git
- [ ] Sensitive files in .gitignore (if applicable)
- [ ] `<target_file>.backup` present and byte-identical to the pre-migration
      original — asserted by `lib/symlink_migrate.sh`, whose zero exit status
      is the proof. Do not tick this by inspection; if the helper exited
      non-zero it already rolled the original back and the run is a `[FAIL]`.
