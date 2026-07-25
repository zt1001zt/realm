# RS Manager Unified Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tested one-command manager for Sing-box protocol instances, Realm forwarding, and reversible BBR/TCP tuning.

**Architecture:** `install.sh` installs a modular Bash application. Native Sing-box JSON and Realm TOML remain authoritative; shared core modules provide validation, service adapters, state, transactions, and rollback. Interactive menus call testable non-interactive module functions.

**Tech Stack:** Bash 4+, jq, curl, openssl, Linux utilities, shell tests, ShellCheck, Go panel tests.

## Global Constraints

- Support Debian/Ubuntu, CentOS/RHEL-compatible distributions, Alpine, systemd, and OpenRC.
- Preserve unknown content in `/etc/sing-box/config.json` and `/root/.realm/config.toml`.
- Never replace kernels, reboot, or modify firewall, SSH, or DNS without explicit confirmation.
- Write sysctl settings only to `/etc/sysctl.d/99-rs-manager.conf`.
- Use restricted temporary paths, backups, candidate validation, atomic replacement, health checks, and rollback.
- Retain MIT attribution for adapted BBR/TCP concepts.

---

### Task 1: Test Harness and Platform Core

**Files:** Create `tests/test_helper.sh`, `tests/core_test.sh`, `lib/core/common.sh`, `lib/core/system.sh`, `lib/core/validation.sh`, `lib/core/service.sh`.

**Interfaces:** Produce `rs_detect_platform ROOT`, `rs_validate_port PORT`, `rs_validate_host HOST`, `rs_port_is_used PORT`, and `rs_service ACTION NAME`.

- [ ] Write table-driven tests for Debian→`apt/systemd`, Alpine→`apk/openrc`, valid/invalid ports and hosts, and fake systemd/OpenRC dispatch.
- [ ] Run `bash tests/core_test.sh`; verify failure because core functions are missing.
- [ ] Implement `RS_ROOT`-aware platform detection, common path helpers, validators, and one service adapter for `start|stop|restart|enable|disable|is-active|status`.
- [ ] Run `bash tests/core_test.sh`; verify all assertions pass.

### Task 2: Transaction and Metadata Core

**Files:** Create `tests/transaction_test.sh`, `lib/core/transaction.sh`, `lib/core/state.sh`.

**Interfaces:** Produce `rs_lock_acquire`, `rs_lock_release`, `rs_backup_create NAME FILE...`, `rs_atomic_install CANDIDATE TARGET`, `rs_backup_rotate`, `rs_state_init`, `rs_state_get`, and `rs_state_set`.

- [ ] Test temporary-root backups, atomic replacement, validation failure preserving targets, rotation to ten automatic backups, named backup preservation, and JSON state round-trips.
- [ ] Run `bash tests/transaction_test.sh`; verify failure because functions are missing.
- [ ] Implement PID-marked directory locks, `mktemp -d`, `cp -a`, same-directory temp targets plus `mv`, and jq state updates through temporary files.
- [ ] Run `bash tests/transaction_test.sh`; verify all assertions pass.

### Task 3: Sing-box Instance Lifecycle

**Files:** Create `tests/fixtures/singbox-existing.json`, `tests/singbox_test.sh`, `lib/modules/singbox.sh`.

**Interfaces:** Produce `rs_sb_list`, `rs_sb_add TYPE NAME PORT`, `rs_sb_edit TAG FIELD VALUE`, `rs_sb_delete TAG`, `rs_sb_clone TAG NAME PORT`, `rs_sb_link TAG HOST`, `rs_sb_migrate`, and `rs_sb_validate FILE`.

- [ ] Test that a legacy SS fixture plus custom DNS/route/outbound/experimental fields survives adding HY2 and VLESS; duplicate types get unique tags; exact-tag edit/delete affects one instance; clone gets new credentials; migration discovers legacy entries.
- [ ] Run `bash tests/singbox_test.sh`; verify failure because lifecycle functions are missing.
- [ ] Implement jq protocol builders, credential generation, exact-tag mutations, port rejection, custom-field preservation, all five share-link formats, and migration metadata.
- [ ] Run `bash tests/singbox_test.sh`; verify all assertions pass.

### Task 4: Realm Rule Lifecycle

**Files:** Create `tests/fixtures/realm-existing.toml`, `tests/realm_test.sh`, `lib/modules/realm.sh`.

**Interfaces:** Produce `rs_realm_list`, `rs_realm_add ID LISTEN REMOTE`, `rs_realm_edit ID LISTEN REMOTE`, `rs_realm_delete ID`, `rs_realm_toggle ID STATE`, `rs_realm_add_range START END HOST REMOTE_START`, `rs_realm_import_link LINK LISTEN`, and `rs_realm_validate FILE`.

- [ ] Test preservation of network settings/comments, migration, add/edit/disable/enable/delete, sequential ranges, duplicate listeners, and share-link host/port parsing.
- [ ] Run `bash tests/realm_test.sh`; verify failure because functions are missing.
- [ ] Implement marker-backed rules using `# rs:id=<id>` and optional `# rs:disabled`; preserve unrelated TOML byte-for-byte and mutate by marker ID.
- [ ] Run `bash tests/realm_test.sh`; verify all assertions pass.

### Task 5: Reversible Tuning and Diagnostics

**Files:** Create `tests/tuning_test.sh`, `tests/diagnostics_test.sh`, `lib/modules/tuning.sh`, `lib/modules/diagnostics.sh`, `THIRD_PARTY_NOTICES.md`.

**Interfaces:** Produce `rs_tune_status`, `rs_tune_render PROFILE`, `rs_tune_preview PROFILE`, `rs_tune_apply PROFILE`, `rs_tune_restore`, `rs_tune_realm`, `rs_diag_run`, and `rs_diag_redact`.

- [ ] Test memory-profile caps, BBR/fq output, manager-only sysctl ownership, restore, and redaction of passwords, UUIDs, tokens, Reality keys, and addresses.
- [ ] Run `bash tests/tuning_test.sh && bash tests/diagnostics_test.sh`; verify failure because functions are missing.
- [ ] Implement previewable profiles, captured prior runtime values, manager-only sysctl writes, default-route-only fq, reversible Realm tuning, read-only diagnostics, secret redaction, and MIT notice.
- [ ] Run both tests; verify all assertions pass.

### Task 6: CLI, Installer, Docs, Review, and Publication

**Files:** Create `tests/cli_test.sh`, `tests/run.sh`, `bin/rs`, `install.sh`, `rs-manager.sh`, `checksums.txt`; modify `README.md`.

**Interfaces:** Produce `rs` main menu, `sb` compatibility entry, standalone `rs-manager.sh`, and one-command installer.

- [ ] Test `--help`, Sing-box/Realm/tuning/diagnostic dispatch, `RS_PREFIX` installation, and creation of `rs` plus `sb` launchers.
- [ ] Run `bash tests/cli_test.sh`; verify failure because CLI and installer are missing.
- [ ] Implement CLI menus, non-interactive dispatch, verified bundle installation, standalone download script, and configuration-preserving updates.
- [ ] Document installation, commands, supported systems, migration, protocol addition, Realm, tuning warnings, restore, and uninstall.
- [ ] Run `bash tests/run.sh`, `shellcheck install.sh rs-manager.sh bin/rs lib/core/*.sh lib/modules/*.sh tests/*.sh`, `go test ./...` from `web/`, and `git diff --check`; require zero failures/findings.
- [ ] Review the complete diff against design and plan, commit intended files on `agent/rs-manager`, push to `origin`, and open a draft PR with validation and risk notes.
