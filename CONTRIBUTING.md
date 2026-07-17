# Contributing to aimeter

## Setup

Requires Xcode Command Line Tools (`swiftc`), targeting macOS 14.0+. `make vendor-sparkle` downloads the vendored Sparkle xcframework when missing; `swift test` uses `Package.swift` and does not link Sparkle.

## Project layout

```
Sources/        App code — see AGENTS.md for per-file breakdown
Tests/          SPM unit tests
Package.swift   SPM manifest — tests only; the app still builds via Makefile
Makefile        Build commands
```

The per-file architecture, release constraints, and signing notes live in
`AGENTS.md`.

## Making changes

1. Run `swift test`
2. Build with `make build`
3. Test with both providers if possible (Claude Code + Codex)
4. Test single-provider scenarios (only Claude or only Codex installed)
5. If you change release/build logic, also run `make universal`
6. If you change UI, attach a screenshot to your PR

## What we'd love

- More test coverage around Settings, Sparkle update UI, and release edge cases
- Linux/Windows ports (via cross-platform Swift?)
- Additional AI provider support (e.g., GitHub Copilot CLI)
- Localization beyond English/Chinese

## What to avoid

- Adding runtime dependencies without a clear reason; Sparkle is intentionally vendored and isolated from `swift test`
- Changes that require user intervention beyond the existing setup dialog
- UI changes that increase menu bar width (it's deliberately compact)

## Code style

- Match existing style — terse, no excessive comments
- Keep files scoped to one concern even when a parser or view needs to be larger
- All disk I/O on background threads, all `@Published` updates on main
- Use existing `S.zh` localization helper for any user-facing strings

## Reporting issues

Include:
- macOS version
- Output of `ls ~/.claude/projects/ | wc -l` (Claude data scale)
- Output of `find ~/.codex/sessions -name 'rollout-*.jsonl' | wc -l` (Codex data scale)
- Whether Claude Code and/or Codex are installed
- Whether you changed the Claude/Codex root directories in Settings
- Console output if there's a crash (Console.app → search "aimeter")
