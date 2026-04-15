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

1. Bump 版本号：
   - `Info.plist`：`CFBundleShortVersionString` 改 marketing 版本（如 `0.2.0`）；`CFBundleVersion` 递增 build 号（整数，严格单调递增，不能重复或回退）
   - `CHANGELOG.md`：`[Unreleased]` 改为新版本号 + 日期
2. 本地验证：`rm -rf build && make release` 生成 `build/aimeter.zip`（ad-hoc 签名，仅验证编译）
3. commit + push main
4. 打 tag：`git tag vX.Y.Z && git push origin vX.Y.Z`
5. GitHub Action (`.github/workflows/release.yml`) 自动：
   - 从 Secrets 恢复 Developer ID 证书到临时 keychain + 注册 notarytool profile
   - 编译 universal binary → Developer ID 签名（Hardened Runtime + secure timestamp）
   - 提交 Apple notary service → staple ticket → 重新打包 zip
   - 创建 GitHub Release + 跨 repo 推 Homebrew cask
   - 签名 secret 缺失时自动降级为 ad-hoc zip（不会 break）
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

### Secrets 配置

release.yml 使用 7 个 GitHub Secrets。签名相关的 6 个缺任何一个都会自动降级为 ad-hoc 发布：

| Secret | 用途 |
|--------|------|
| `DEVELOPER_ID_APPLICATION` | 证书名，形如 `Developer ID Application: Your Name (TEAMID)` |
| `DEVELOPER_ID_CERT_P12` | 证书 .p12 的 base64（`base64 -i cert.p12 \| pbcopy`） |
| `DEVELOPER_ID_CERT_PASSWORD` | 导出 .p12 时设置的密码 |
| `NOTARY_API_KEY_P8` | App Store Connect API Key 的 .p8 base64 |
| `NOTARY_KEY_ID` | API Key 的 Key ID（10 字符） |
| `NOTARY_ISSUER_ID` | Team Issuer ID（UUID） |
| `HOMEBREW_TAP_TOKEN` | 跨 repo 推 tap 的 fine-grained PAT |

**Notary API Key 获取**：App Store Connect → Users and Access → Integrations → Team Keys → 新建 Key（Access 选 Developer 即可）。.p8 文件**只能下载一次**，保存好。

**Developer ID 证书导出**：Xcode → Settings → Accounts → Manage Certificates → 右键 Developer ID Application → Export Certificate → 设密码保存 .p12。

**HOMEBREW_TAP_TOKEN**：fine-grained PAT，只勾 `homebrew-aimeter` repo + Contents: Read and write。生成后 `gh secret set HOMEBREW_TAP_TOKEN --repo wangyufeng0615/aimeter`。

### 发布后端到端验证

```bash
brew untap wangyufeng0615/aimeter 2>/dev/null || true
brew tap wangyufeng0615/aimeter
brew install --cask aimeter
open /Applications/aimeter.app
# 公证通过的 app 首次启动不会被 Gatekeeper 拦
# 可选验证：spctl -a -vvv -t install /Applications/aimeter.app  # 期望 source=Notarized Developer ID
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

### 签名与公证

**发布产物**：Developer ID 签名 + Hardened Runtime + Apple Notary Service 公证 + ticket staple。用户双击即运行。

**本地开发**：`make build` / `make release` 走 ad-hoc 签名（仍启用 Hardened Runtime，保持行为和发布一致）。无需证书。

**CI 降级**：`DEVELOPER_ID_*` / `NOTARY_*` secret 任一缺失时，release.yml 自动发 ad-hoc zip，不 break 流程。降级发布的 release notes 会自动提示用户如何绕过 Gatekeeper。

### 本地 notarize（可选）

一次性存 notary 凭证到 Keychain：
```bash
xcrun notarytool store-credentials aimeter-notary \
    --key ~/Downloads/AuthKey_XXXXX.p8 \
    --key-id XXXXX \
    --issuer XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

之后本地完整走一遍签名+公证：
```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" make notarize
# 产出 build/aimeter.zip（含 stapled .app）
```

Makefile 通过 `DEVELOPER_ID` 环境变量自动切换签名模式，留空则 ad-hoc。`NOTARY_PROFILE` 默认 `aimeter-notary`。
