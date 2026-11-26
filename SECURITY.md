# Security Policy

## Reporting a Vulnerability

If you believe you've found a security issue in aimeter, **do not open a public issue**.

Use GitHub's [Privately Report a Vulnerability](https://github.com/wangyufeng0615/aimeter/security/advisories/new) feature instead. You should expect an acknowledgement within 7 days.

## Scope

aimeter runs entirely on your local machine. It reads from the default roots
(`~/.claude`, `~/.codex`, `~/.gemini`) or the custom roots configured in Settings:

- `<Claude root>/projects/**/*.jsonl` — Claude Code conversation logs
- `<Claude root>/usage-rate.json` — rate-limit snapshot written by the statusline hook
- `~/Library/Application Support/Claude/plan-usage-history.json` — Claude Desktop subscription-limit snapshots (percentages only)
- `<Claude root>/settings.json` — inspected or edited only for hook setup/removal
- `<Codex root>/sessions/**/rollout-*.jsonl` — Codex token-count and rate-limit events
- `<Gemini root>/antigravity{,-cli}/conversations/*.db` — Antigravity IDE/CLI conversation databases, opened read-only (only per-generation token counts, model IDs and step timestamps are decoded)
- `<Gemini root>/antigravity{,-cli}/daemon/hub_*.json` — loopback port, process ID and per-launch CSRF token of the running Antigravity language server (kept in memory only)
- `<Gemini root>/tmp/*/chats/session-*.json` — Gemini CLI chat recordings (token counts only)

It writes:

- `<Claude root>/settings.json` — first launch or Settings only, with user consent, to add/remove a `tee` hook for rate-limit data
- `<Claude root>/settings.json.bak-<timestamp>` — automatic backup before any edit (last 3 kept)
- `~/Library/Caches/com.aimeter.app/claude-rate-v1-<root-hash>.json` — cached Claude rate-limit snapshot
- `~/Library/Caches/com.aimeter.app/pricing.json` — LiteLLM pricing cache (24h TTL; early refresh for missing direct-model prices, with attempts at least 15 minutes apart)
- `~/Library/Preferences/com.aimeter.app.plist` — app preferences such as language, launch-at-login flag, and custom roots

## Network

Automatic outbound requests are limited to:

- Model pricing from
  `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`.
- Sparkle's appcast from
  `https://raw.githubusercontent.com/wangyufeng0615/aimeter/main/docs/appcast.xml`.

Local-only requests: while Antigravity is running, aimeter calls its language
server's `GetUserStatus` on `http://127.0.0.1:<port>` once a minute to read model
quota fractions and reset times. aimeter itself only connects to 127.0.0.1;
the language server answers with the quota state it already keeps for the
Antigravity UI and may refresh it from Google's servers as it normally does.

After the user approves an available update, Sparkle downloads the release zip
referenced by the signed appcast from GitHub Releases. The app does not attach
CLI logs or usage records to these requests and has no product telemetry.

## Supported Versions

Only the latest release receives security fixes.
