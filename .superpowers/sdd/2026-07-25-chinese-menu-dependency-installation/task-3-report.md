# Task 3 Report

## Delivered

- Added `rs_tune_smart_preview()`. It prints the kernel/status, memory in KiB,
  open-file limit, performs the existing BBR support check, and previews the
  standard BBR/TCP sysctl configuration.
- Replaced the main, Sing-box, Realm, service, and tuning menu labels, options,
  prompts, and action failures with UTF-8 Chinese numeric menus.
- Added the BBR/TCP smart-tuning menu entry. It previews before asking
  `确认应用智能调优？ [y/N]`, and only `y`/`Y` applies the standard profile.
- Added tests for the UTF-8 main menu, Chinese child-menu options, smart-preview
  output, and declined/confirmed smart-tuning flows.

## TDD evidence

- **Red:** `tests/tuning_test.sh` stopped at
  `rs_tune_smart_preview: command not found` before the implementation.
- **Red:** `tests/cli_test.sh` reported the new Chinese-menu and smart-tuning
  assertions as failures before the menu rewrite.
- **Green:** `C:\Program Files\Git\bin\bash.exe tests/tuning_test.sh` passed
  all 16 assertions after implementation.

## Verification

- `C:\Program Files\Git\bin\bash.exe -n bin/rs lib/modules/tuning.sh tests/cli_test.sh tests/tuning_test.sh` — passed.
- `git diff --check` — passed.
- `C:\Program Files\Git\bin\bash.exe tests/cli_test.sh` reached `ok 1`
  through `ok 19`, including every new Task 3 assertion. It then exits nonzero
  in the existing installer checksum stage: `checksums.txt` is intentionally
  outside Task 3 and is already stale for `lib/modules/singbox.sh`; this task
  also changes `bin/rs` and `lib/modules/tuning.sh`. Checksum regeneration is
  assigned to Task 4.

## Scope

No panel, automatic installation, restart behavior, or unrelated refactor was
added. The pre-existing untracked `.tmp-test-bin/` directory was left untouched.
