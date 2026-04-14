# aimeter

macOS menu bar app，监控 Claude Code 和 Codex CLI 的用量。

## 构建

```bash
make build      # 编译 → build/aimeter.app（当前架构）
make universal  # 编译 arm64 + x86_64 通用二进制
make run        # 编译并启动
make install    # 安装到 ~/Applications/
make release    # universal + zip，用于发布
make clean      # 清理
swift test      # 跑单元测试（SPM，不走 Makefile）
```

需要 Xcode Command Line Tools（`swiftc`），目标 macOS 14.0+。

## 架构

纯 SwiftUI + AppKit，无外部运行时依赖。app 本体用 `swiftc` 通过 Makefile 直接编译；`Package.swift` 仅用于跑 SPM 测试（`swift test`），不参与 app 构建。

- **数据层**：两个独立来源
  - Claude Code：`~/.claude/projects/**/*.jsonl`（JSONL 对话日志）+ `~/.claude/usage-rate.json`（statusline hook 写入的 rate limit）
  - Codex：`~/.codex/state_5.sqlite`（线程汇总）+ `~/.codex/sessions/**/rollout-*.jsonl`（session 级 rate limit）
- **定价层**：启动时从 LiteLLM GitHub 拉取最新定价，缓存到 `~/Library/Caches/com.aimeter.app/pricing.json`（24h TTL），离线用硬编码默认值
- **刷新**：rate limit 每 15 秒读一次，JSONL 解析也每 15 秒（有文件级缓存，mod+size 双校验）

## 文件说明

| 文件 | 职责 |
|------|------|
| App.swift | 入口，MenuBarExtra + 自定义 label |
| SetupHelper.swift | 首次启动检测 + 自动注入 statusline tee |
| UsageStore.swift | ObservableObject，两阶段异步加载（Stage 1 rate limit → Stage 2 JSONL） |
| RateReader.swift | 读 Claude statusline JSON + Codex session JSONL 的 rate_limits |
| CodexReader.swift | SQLite3 C API 读 Codex threads 表 |
| Pricing.swift | LiteLLM 定价获取/缓存/阶梯计费 + Codex 混合费率估算 |
| Models.swift | UsageEntry, DailyUsage, ModelUsage |
| DetailView.swift | 面板 UI：rate cards, today stats, model chart, weekly chart |
| Settings.swift | 设置面板 UI：启动项、语言、隐私说明 |
| Colors.swift | Light/dark 动态颜色 + hex 解析 |
| Strings.swift | 中英文自动切换（跟随系统 locale） |

## 关键设计决策

- **Rate limit 百分比来自服务端**，不本地计算。Claude 通过 statusline hook（`tee` 写文件），Codex 从 session JSONL 的 `token_count` 事件读取。
- **首次启动自动配置 statusline hook**：避免用户手动改 settings.json，弹一次性对话框获得授权。
- **费用采用 ccusage 的 auto 模式**：JSONL 有 `costUSD` 字段就用，没有就按 LiteLLM 定价计算。
- **Codex 费用是估算**：SQLite 只有 `tokens_used` 总量无 input/output 分拆，用 90%/9%/1% 混合费率。
- **fileCache 线程安全**：主线程快照 → 后台用 inout 副本 → 主线程回写，`stage2InFlight` 防并发。
- **Codex session 文件用容错 UTF-8 解码**（`String(decoding:as:UTF8.self)`），因为从文件中间读取可能截断多字节字符。

## 注意事项

- `Pricing.rates` 用 `NSLock` 保护，因为后台线程写、主线程读
- `Pricing.loadFromLiteLLM()` 用信号量同步阻塞，但 app 生命周期内只调用一次（`pricingLoaded` 标志）
- 修改 settings.json 用 `.atomic` 写入，防止崩溃留下损坏文件
- Info.plist 的 `LSUIElement=true` 隐藏 Dock 图标，`LSMinimumSystemVersion=14.0`

## 发布流程

### 新版本发布步骤

1. Bump 版本号（两处要同步）：
   - `Info.plist`：`CFBundleShortVersionString` + `CFBundleVersion`
   - `CHANGELOG.md`：`[Unreleased]` 改为新版本号 + 日期
2. 本地验证：`rm -rf build && make release` 生成 `build/aimeter.zip`
3. commit + push main
4. 打 tag：`git tag vX.Y.Z && git push origin vX.Y.Z`
5. GitHub Action (`.github/workflows/release.yml`) 自动：
   - 用 macOS runner 编译 universal binary → zip
   - 创建 GitHub Release（附 zip + SHA256 in body）
   - 跨 repo 推 `Casks/aimeter.rb` bump version/sha256 到 tap
6. 验证：`gh run watch --repo wangyufeng0615/aimeter`

### Homebrew Tap

- GitHub：https://github.com/wangyufeng0615/homebrew-aimeter
- 本地开发路径：`/path/to/homebrew-aimeter/`
- 内容：仅 `Casks/aimeter.rb` + README + LICENSE
- **手动不要改 `Casks/aimeter.rb`**，每次 tag 触发时 release workflow 自动覆盖

用户安装命令：
```bash
brew tap wangyufeng0615/aimeter
brew install --cask aimeter
```

### `HOMEBREW_TAP_TOKEN` secret

release.yml 的 "Bump Homebrew tap" step 需要跨 repo 写 tap 仓库，要 `secrets.HOMEBREW_TAP_TOKEN`。推荐用 fine-grained PAT：
- 打开 https://github.com/settings/personal-access-tokens/new
- Repository access: 只勾 `homebrew-aimeter`
- Permissions → Repository permissions → Contents: Read and write
- 生成后：`gh secret set HOMEBREW_TAP_TOKEN --repo wangyufeng0615/aimeter`

### 发布后端到端验证

```bash
brew untap wangyufeng0615/aimeter 2>/dev/null || true
brew tap wangyufeng0615/aimeter
brew install --cask aimeter
open /Applications/aimeter.app
# 首次启动被 Gatekeeper 拦时：System Settings → Privacy & Security → Open Anyway
```

### 手动修复 tap（Action 挂了时的 fallback）

```bash
cd /path/to/homebrew-aimeter
VERSION=X.Y.Z
ZIP_URL="https://github.com/wangyufeng0615/aimeter/releases/download/v${VERSION}/aimeter.zip"
SHA256=$(curl -sL "$ZIP_URL" | shasum -a 256 | cut -d' ' -f1)
# 编辑 Casks/aimeter.rb，把 version 和 sha256 替换掉
git commit -am "aimeter ${VERSION}"
git push
```

### 签名现状

当前 ad-hoc 签名（`codesign --sign -`），未 notarize。用户首次启动要走 **System Settings → Privacy & Security → Open Anyway**。

未来升级路径：买 Apple Developer Program（$99/年）→ 在 release.yml 里加 `codesign --options runtime --sign "Developer ID Application: ..."` + `xcrun notarytool submit` + `xcrun stapler staple`。Homebrew 官方 cask 也会从 2026-09 起要求 notarize，想进主 cask 必须做。
