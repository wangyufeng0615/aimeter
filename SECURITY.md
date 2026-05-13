# Security Policy

## Reporting a Vulnerability

If you believe you've found a security issue in aimeter, **do not open a public issue**.

Use GitHub's [Privately Report a Vulnerability](https://github.com/wangyufeng0615/aimeter/security/advisories/new) feature instead. You should expect an acknowledgement within 7 days.

## Scope

aimeter runs entirely on your local machine. It reads from the default roots
(`~/.claude`, `~/.codex`) or the custom roots configured in Settings:

- `<Claude root>/projects/**/*.jsonl` — Claude Code conversation logs
- `<Claude root>/usage-rate.json` — rate-limit snapshot written by the statusline hook
- `<Claude root>/settings.json` — inspected or edited only for hook setup/removal
- `<Codex root>/sessions/**/rollout-*.jsonl` — Codex token-count and rate-limit events

It writes:

- `<Claude root>/settings.json` — first launch or Settings only, with user consent, to add/remove a `tee` hook for rate-limit data
- `<Claude root>/settings.json.bak-<timestamp>` — automatic backup before any edit (last 3 kept)
- `~/Library/Caches/com.aimeter.app/claude-rate-v1-<root-hash>.json` — cached Claude rate-limit snapshot
- `~/Library/Caches/com.aimeter.app/pricing.json` — LiteLLM pricing cache (24h TTL)
- `~/Library/Preferences/com.aimeter.app.plist` — app preferences such as language, launch-at-login flag, and custom roots

## Network

The only outbound request is fetching model pricing from `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`. No telemetry, no personal data.

## Supported Versions

Only the latest release receives security fixes.
