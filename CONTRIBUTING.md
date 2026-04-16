# Contributing to aimeter

## Setup

Requires Xcode Command Line Tools (`swiftc`), targeting macOS 14.0+. See [CLAUDE.md](CLAUDE.md) for build commands (`make build`, `make run`, `swift test`).

## Project layout

```
Sources/        App code — see CLAUDE.md for per-file breakdown
Tests/          SPM unit tests
Package.swift   SPM manifest — tests only; the app still builds via Makefile
Makefile        Build commands
```

## Making changes

1. Build and verify: `make build && make run`
2. Test with both providers if possible (Claude Code + Codex)
3. Test single-provider scenario (only Claude or only Codex installed)
4. If you change UI, attach a screenshot to your PR

## What we'd love

- More test coverage (currently: UsageStoreTests, SetupHelperTests, PricingTests)
- Linux/Windows ports (via cross-platform Swift?)
- Additional AI provider support (e.g., GitHub Copilot CLI)
- Localization beyond English/Chinese
- Better cost estimation for Codex (parse session JSONL for per-request token splits)

## What to avoid

- Adding external dependencies (the project values its zero-dependency design)
- Changes that require user intervention beyond the existing setup dialog
- UI changes that increase menu bar width (it's deliberately compact)

## Code style

- Match existing style — terse, no excessive comments
- One file per concern; keep files under 250 lines
- All disk I/O on background threads, all `@Published` updates on main
- Use existing `S.zh` localization helper for any user-facing strings

## Reporting issues

Include:
- macOS version
- Output of `ls ~/.claude/projects/ | wc -l` (Claude data scale)
- Whether Claude Code and/or Codex are installed
- Console output if there's a crash (Console.app → search "aimeter")
