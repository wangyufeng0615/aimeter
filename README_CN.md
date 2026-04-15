# aimeter

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English README](README.md)

一个轻量级 macOS 菜单栏应用，实时监控你的 [Claude Code](https://code.claude.com/) 和 [Codex CLI](https://github.com/openai/codex) 用量。

<p align="center">
  <img src="docs/screenshot.png" alt="aimeter 菜单栏弹窗" width="300">
</p>

## 特性

- 直接展示 Claude Code 和 Codex 官方 API 返回的 5h / 7d rate limit，不是本地估算
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

> **首次启动**：macOS 会拦截，提示 *"Apple could not verify 'aimeter.app' is free of malware…"*（因为 app 未经 notarize）。先点 **Done**（⚠️ 不要点 Move to Bin，那会删掉 app），然后打开 **系统设置 → 隐私与安全性**，往下滚，在 aimeter 提示旁点 **仍要打开**，用密码或 Touch ID 确认。以后再打开就正常了。
>
> 如果装了 Claude Code，aimeter 还会弹窗请求在 `~/.claude/settings.json` 里加一条 `tee` hook，用于读取 rate limit。Codex 无需额外配置。

## 隐私

aimeter 完全在本地运行。唯一的外部请求是从 [LiteLLM](https://github.com/BerriAI/litellm) GitHub 拉取定价数据——无遥测、无个人数据。详见 [SECURITY.md](SECURITY.md)。

## 开发

构建和贡献指南见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE)。定价数据来自 [LiteLLM](https://github.com/BerriAI/litellm)；费用计算方式参考了 [ccusage](https://github.com/ryoppippi/ccusage)。
