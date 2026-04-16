# aimeter

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/wangyufeng0615/aimeter/total)](https://github.com/wangyufeng0615/aimeter/releases)
[![Last commit](https://img.shields.io/github/last-commit/wangyufeng0615/aimeter)](https://github.com/wangyufeng0615/aimeter/commits)

[English README](README.md)

一个轻量级 macOS 菜单栏应用，实时监控你的 [Claude Code](https://code.claude.com/) 和 [Codex CLI](https://github.com/openai/codex) 用量。

> 作者日常自用的工具，会精心长期维护。

<p align="center">
  <img src="docs/screenshot.png" alt="aimeter 菜单栏弹窗" width="300">
</p>

## 特性

- 准确显示 5 小时限额 / 周限额
- 展示 token 用量和费用
- 只用 Claude Code / Codex 其中一个？另一个的面板会自动隐藏
- 数据全部来自官方 CLI 的本地文件，不经任何第三方接口

## 安装

```bash
brew tap wangyufeng0615/aimeter && brew install --cask aimeter
```

或从 [Releases](https://github.com/wangyufeng0615/aimeter/releases) 下载 zip。

自动更新：aimeter 每天自动检查新版本，在 app 内提示升级；也可以在设置 → 更新里手动触发，或直接运行 `brew upgrade --cask aimeter`。

> 首次启动会请求给 Claude Code 加 statusline hook，用于读取 rate limit。Codex 无需配置。

## 隐私

完全本地运行。唯一外部请求：从 [LiteLLM](https://github.com/BerriAI/litellm) 拉取定价数据。无遥测。详见 [SECURITY.md](SECURITY.md)。

## 开发

构建和贡献指南见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)。定价数据来自 [LiteLLM](https://github.com/BerriAI/litellm)；费用计算方式参考了 [ccusage](https://github.com/ryoppippi/ccusage)。
