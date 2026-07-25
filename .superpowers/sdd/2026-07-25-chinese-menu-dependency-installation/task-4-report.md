# Task 4 Report

## Delivered

- Regenerated every entry in `checksums.txt` from its Git LF blob with `git cat-file blob "HEAD:<path>" | sha256sum`, rather than hashing the Windows working-tree files. The refreshed entries cover the prior Task 1–3 changes to `bin/rs`, `lib/modules/singbox.sh`, and `lib/modules/tuning.sh`; unchanged listed files retain their verified digests.
- Added a README section for the Chinese numeric menu, confirmation-gated Sing-box dependency installation, and the smart BBR/TCP preview, `y`/`Y` confirmation, and restore flow.

## Scope preserved

- Did not change the release version, Git tag references, bootstrap script, or bootstrap bundle SHA-256. Those stay pending the Ubuntu CI bundle SHA after the main-branch push.
- Left the pre-existing untracked `.tmp-test-bin/` Python shim untouched; it was used only through `PATH` for the test run.

## Verification

- `git ls-files -z "*.sh" | xargs -0 bash -n` passed.
- `PATH="$PWD/.tmp-test-bin:/usr/bin:/bin:$PATH" bash tests/run.sh` passed all suites (`core`, `transaction`, `singbox`, `realm`, `tuning`, `diagnostics`, `deployment`, `cli`, and `release`) on 2026-07-25.
- `git diff --check` passed.
- The release test independently verified every listed checksum against `HEAD:<path>` Git blobs and passed, including the LF/CRLF deterministic bundle checks.