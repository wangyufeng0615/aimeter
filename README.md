# aimeter

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/wangyufeng0615/aimeter/total)](https://github.com/wangyufeng0615/aimeter/releases)
[![Last commit](https://img.shields.io/github/last-commit/wangyufeng0615/aimeter)](https://github.com/wangyufeng0615/aimeter/commits)

[中文 README](README_CN.md)

A lightweight macOS menu bar app that tracks your [Claude Code](https://code.claude.com/) and [Codex CLI](https://github.com/openai/codex) usage in real time.

> A tool I use every day myself — carefully maintained for the long haul.

<p align="center">
  <img src="docs/screenshot.png" alt="aimeter menu bar popover" width="300">
</p>

## Features

- Accurate 5-hour / weekly usage limits
- Token usage and cost breakdown
- Only use Claude Code or Codex? The other's panel stays hidden
- All data comes from the official CLIs' local files — no third-party services

## Install

```bash
brew tap wangyufeng0615/aimeter && brew install --cask aimeter
```

Or grab the zip from [Releases](https://github.com/wangyufeng0615/aimeter/releases).

Updates are automatic — aimeter checks once a day and prompts inside the app. You can also trigger a check from Settings → Updates, or run `brew upgrade --cask aimeter` yourself.

> First launch asks to add a statusline hook for Claude Code. Codex needs no setup.

## Privacy

Runs entirely on your machine. One outbound request: pricing data from [LiteLLM](https://github.com/BerriAI/litellm). No telemetry. See [SECURITY.md](SECURITY.md).

## Development

Build and contribution guide in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Pricing data from [LiteLLM](https://github.com/BerriAI/litellm); cost calculation inspired by [ccusage](https://github.com/ryoppippi/ccusage).
