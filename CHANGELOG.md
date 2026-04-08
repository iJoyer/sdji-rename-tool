# Changelog

All notable changes to this project will be documented in this file.

## [0.2.2] - 2026-04-08

### Added
- Added rename confirmation prompt before applying changes.
- Added `--yes` to skip rename confirmation in non-interactive use.
- Added `--undo-last` to restore previous rename batch from log.
- Added `--clear-log` and `--log-file` to control undo log lifecycle.
- Added npm/pnpm global install entry (`pic-rename` wrapper).

### Changed
- Improved DJI timestamp removal to work when `DJI_` appears with arbitrary prefix.
- Fixed marker-chain behavior to preserve keep markers (for example `-T`) while removing edit markers.
- Improved safety for hyphen-chain cleanup to avoid truncating filename prefixes.
- Default log path moved to `/tmp/pic-rename/rename_log.csv`, and logging is enabled by default.
- Rename log now includes `base_dir` for cross-directory `--undo-last`.

### Fixed
- Fixed false truncation case like `0815-DJI_...` becoming overly short.
- Fixed undo path resolution issues when command is run from a directory different from rename execution directory.
