# Security Policy

## Reporting a Vulnerability

If you believe you've found a security issue in aimeter, **do not open a public issue**.

Use GitHub's [Privately Report a Vulnerability](https://github.com/wangyufeng0615/aimeter/security/advisories/new) feature instead. You should expect an acknowledgement within 7 days.

## Scope

aimeter runs entirely on your local machine. It reads:

- `~/.claude/projects/**/*.jsonl` — Claude Code conversation logs
- `~/.claude/usage-rate.json` — rate limit snapshot written by the statusline hook
- `~/.codex/sessions/**/rollout-*.jsonl` — Codex session logs
- `~/.codex/state_5.sqlite` — Codex thread summaries

It writes:

- `~/.claude/settings.json` — first launch only, with user consent, to add a `tee` hook for rate limit data
- `~/.claude/settings.json.bak-<timestamp>` — automatic backup before any edit (last 3 kept)
- `~/Library/Caches/com.aimeter.app/pricing.json` — LiteLLM pricing cache (24h TTL)

## Network

The only outbound request is fetching model pricing from `raw.githubusercontent.com/BerriAI/litellm/…`. No telemetry, no personal data.

## Supported Versions

Only the latest release receives security fixes.
