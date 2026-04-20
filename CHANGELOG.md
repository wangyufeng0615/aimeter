# Changelog

## [0.3.1] - 2026-04-20

### Added
- Settings: "Paths" section — override `~/.claude` / `~/.codex` roots for non-standard installs. Auto-commit on Return or focus loss; inline warning if the directory doesn't exist.
- `AppPaths` centralizes all path resolution; user-configured roots propagate to JSONL reading, rate readers, and statusline hook install/uninstall.
- `UsageStore` listens for path changes and reloads (drops caches + stage guard via `loadGeneration`).

### Changed
- Menu bar label shortened: "Claude X%" instead of "Claude Code X%".
- Detail view shows the Codex rate card whenever Codex is installed (with a "waiting for first message" empty state), matching Claude's behaviour.
- Per-model breakdown filters out internal `<synthetic>` Claude entries.

### Fixed
- `SetupHelper` hook uninstall now strips both unquoted (`tee ~/.claude/...`) and shell-quoted (`tee '/custom path/...'`) tee prefixes.
- Choose… button in Path rows no longer commits an unconfirmed draft if the file panel is cancelled.

## [0.2.0] - 2026-04-16

### Added
- Developer ID signing + Apple notarization (no more Gatekeeper "unverified developer" warning)
- Faster rate limit polling (2-second interval, separate from full reload timer)
- Distinct "waiting for first message" vs "rate limits unavailable" status messages
- SetupHelper unit tests (23 tests covering hook install/uninstall/preflight)
- Pricing tier boundary tests
- Menu bar image caching (prevents redundant re-renders)
- 64MB file size cap for Codex session parsing
- CI test gate in release workflow

### Fixed
- Stage 1 (rate limit) async race condition via in-flight guard

## [0.1.0] - 2026-04-14

Initial release.

### Features
- Real-time Claude Code and Codex CLI rate limit monitoring
- Compact two-line menu bar display when both providers are present
- Daily and weekly token/cost statistics
- Per-model breakdown with cost
- Auto-detection of installed AI tools
- One-click setup that auto-configures Claude Code statusline hook
- Live pricing from LiteLLM with 24h local cache
- Bilingual UI (English/Chinese, follows system locale)
- Universal binary (arm64 + x86_64)
