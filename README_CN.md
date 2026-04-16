# aimeter

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English README](README.md)

一个轻量级 macOS 菜单栏应用，实时监控你的 [Claude Code](https://code.claude.com/) 和 [Codex CLI](https://github.com/openai/codex) 用量。

<p align="center">
  <img src="docs/screenshot.png" alt="aimeter 菜单栏弹窗" width="300">
</p>

## 特性

- 直接读取 Claude Code 和 Codex CLI 本地数据中的 5h / 7d rate limit，不是估算
- 按天 / 按周统计 token 用量和费用，并按模型分别展示
- 中英双语，跟随系统语言自动切换

## 安装

### Homebrew（推荐）

```bash
brew tap wangyufeng0615/aimeter
brew install --cask aimeter
```

### 预编译 zip

从 [Releases](https://github.com/wangyufeng0615/aimeter/releases) 下载，解压后拖进 Applications。

> 如果装了 Claude Code，aimeter 会弹窗请求在 `~/.claude/settings.json` 里加一条 `tee` hook，用于读取 rate limit。Codex 无需额外配置。

## 隐私

aimeter 完全在本地运行。唯一的外部请求是从 [LiteLLM](https://github.com/BerriAI/litellm) GitHub 拉取定价数据——无遥测、无个人数据。详见 [SECURITY.md](SECURITY.md)。

## 开发

构建和贡献指南见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)。定价数据来自 [LiteLLM](https://github.com/BerriAI/litellm)；费用计算方式参考了 [ccusage](https://github.com/ryoppippi/ccusage)。
