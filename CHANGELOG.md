# Changelog

## [0.3.8] - 2026-09-06

### Fixed
- Add GPT-6 Astra, Claude Fable 5.1, and Mythos 5.1 pricing, including Astra's long-context rates and the lower Claude 5.1 cache-read price.
- Keep complete Claude minor versions separate when importing LiteLLM prices; reject regional or custom relay prices as global API fallbacks.
- Remove the cancelled Sonnet 5 September price increase. Refresh GPT-5.6 offline defaults and preserve Sol's launch pricing for usage before its August 21 promotion.
- Include Codex cache-write tokens and recorded GPT-5.6/Astra priority or flex tiers in cost estimates; flag unverified service tiers as partial cost.
- Keep valid Codex limits when another session starts without a rate event, scan past large tool outputs, and expire snapshots by event time instead of file modification time.
- Support secondary-only Codex and weekly-only Claude limits, and reject invalid percentages.
- Avoid dropping Codex usage when cumulative counters restart, reparse same-size Claude log rewrites, and bound incremental reads to the recorded file size.
- Invalidate legacy pricing caches and validate cached prices, tier prices, and thresholds before use.

## [0.3.7] - 2026-08-09

### Fixed
- Display long rate-limit reset intervals as days, hours, and minutes instead of an opaque total-hour count.
- Add Claude Opus 5 standard and fast-mode pricing, and accept fully priced future versions of established Claude product lines from LiteLLM without waiting for an app update.
- Price Sonnet 5 usage by each entry's timestamp so the September price transition cannot reprice historical August usage.
- Recheck the 24-hour pricing cache throughout long-running app sessions and retry transient refresh failures after 15 minutes.
- Keep incomplete future-model rates, custom relay model IDs, and retired Opus 4.7 fast mode fail-closed instead of manufacturing a plausible cost.
- Exclude internal Claude `<synthetic>` entries from the displayed message count.

## [0.3.6] - 2026-07-21

### Changed
- Display billion-scale token usage with a compact `B` suffix, and promote rounded `1000K`/`1000M` values to the next unit.

## [0.3.5] - 2026-07-13

### Added
- Add Claude Sonnet 5 and GPT-5.6 Sol, Terra, and Luna pricing and model-family support.
- Mark totals as partial when a custom or unknown model has no reliable price instead of silently charging it as another model.

### Changed
- Update GitHub build and release workflows to the Node 24-based checkout action.

### Fixed
- Identify Codex 5-hour and 7-day limits by `window_minutes`; when the service returns only a weekly window, promote 7D to the headline display and always show its reset time.
- Apply OpenAI's full-request long-context pricing above 272K input tokens and stop discounting cached input for GPT-5.4 Pro and GPT-5.5 Pro.
- Apply Claude's US-only inference multiplier and current Opus fast-mode availability.

## [0.3.4] - 2026-06-11

### Fixed
- Show the 7-day limit reset time once 7D usage is above 50% and the provider exposes a reset timestamp.
- Add explicit Claude Fable 5, Mythos 5, Opus 4.8, and Opus 4.7 pricing support, including 1-hour prompt-cache write pricing and Opus fast-mode pricing.

## [0.3.3] - 2026-05-13

### Changed
- Clarified documentation around local usage data, the LiteLLM pricing request, custom Claude/Codex roots, and required contributor checks.
- Updated agent handoff docs to describe Codex session JSONL token-count parsing instead of the old SQLite summary path.

### Fixed
- Avoid double-counting repeated Codex `last_token_usage` events when cumulative totals do not advance.
- Add `gpt-5.5` and `gpt-5.5-pro` pricing support so recent Codex sessions are costed with the correct model family.
- Read Codex rate limits from both top-level and payload JSONL shapes, and scope the latest-rollout cache by Codex sessions directory.
- Parse complete Claude JSONL final lines even when the file has no trailing newline.

### Removed
- Removed unused SQLite link flags and stale Codex total-token cost fallback code.

## [0.3.2] - 2026-04-27

### Changed
- Reduced steady-state CPU work by caching Codex session parsing, pruning stale Claude cache entries, and moving daily/weekly UI aggregation into the background token refresh.
- Slowed rate-limit polling to 5 seconds with timer tolerance so the menu bar app wakes the CPU less aggressively.

### Fixed
- Parse final JSONL records even when a Codex rollout file does not end with a trailing newline.
- Avoid reading the Claude statusline snapshot twice during each rate-limit refresh.
- Keep the Launch at Login setting synchronized with macOS and show an inline error if ServiceManagement registration fails.

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
