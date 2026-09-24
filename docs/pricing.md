# Pricing and usage verification

Updated on 2026-09-23. Amounts below are USD per million tokens at standard/global API rates. aimeter estimates API-equivalent token cost; it does not calculate subscription invoices or credit charges.

| Model | Input | Output | Cache read | Cache write |
| --- | ---: | ---: | ---: | ---: |
| Claude Fable / Mythos 5.1 | 10 | 50 | 0.25 | 12.50 (5m), 20 (1h) |
| Claude Opus 5.5 | 4 | 20 | 0.20 | 5 (5m), 8 (1h) |
| Claude Sonnet 5 | 2 | 10 | 0.20 | 2.50 (5m), 4 (1h) |
| GPT-6 Astra | 10 | 50 | 1 | 12.50 |
| GPT-6 Sol | 2 | 10 | 0.20 | 2.50 |
| GPT-6 Luna | 0.10 | 0.50 | 0.01 | 0.125 |
| GPT-5.6 Sol | 4 | 20 | 0.40 | 5 |
| GPT-5.6 Terra | 2 | 12 | 0.20 | 2.50 |
| GPT-5.6 Luna | 0.20 | 1.20 | 0.02 | 0.25 |

## Sources and date rules

- [Fable 5.1 and Mythos 5.1](https://platform.claude.com/docs/en/models/fable-5-1/overview) share prices; Fable 5 retains its separate $1 cache-read rate.
- [Claude Opus 5.5](https://platform.claude.com/docs/en/about-claude/pricing) has a $0.20 cache-read rate and supports Fast mode at 2x the standard token prices, including cache operations.
- [Sonnet 5 announcement, August 10 correction](https://www.anthropic.com/news/claude-sonnet-5): the scheduled September 1 increase was cancelled. The $2/$10 price remains in effect.
- [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra), [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol), [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna), and [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol), [Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra), [Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna): above 272,000 total prompt tokens, the full request uses 2x input/cache prices and 1.5x output prices.
- [August 21 Sol promotion](https://openai.com/index/gpt-5-6/): pre-August-21 usage retains $5/$30 and its original cache/long-context prices. Date boundaries use UTC dates because the announcement does not specify an exact transition time. The current offer is guaranteed at least through November 21; do not schedule an unconfirmed price increase.
- [LiteLLM snapshot](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json) supplies refreshed rates. Direct GPT and Claude model IDs are matched by exact family/snapshot name, not per-model or per-Claude-family allowlists. New models need complete standard input, output, cache-read, and cache-write prices (plus 1-hour cache writes for Claude); a flat price is valid, while any long-context schedule must include all four categories at one threshold. Fast/Flex is estimated only when its explicit prices imply one consistent multiplier across standard and long-context categories; otherwise that tier remains unknown. Claude minor versions remain distinct, and a separately priced Fast variant can be imported without adding its version to code. Custom relay IDs and regional Bedrock prices cannot stand in for global prices.
- [Codex protocol](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs) and [Responses usage conversion](https://github.com/openai/codex/blob/main/codex-rs/codex-api/src/sse/responses.rs): cache writes and cache reads are subsets of total input. Reasoning tokens are already included in output. Recorded thread settings carry model and service tier.

## Cache and parsing behavior

- `pricing.json` has a version-2 envelope. Older caches are discarded; verified defaults are used immediately while prices refresh. Optional validated Fast/Flex multipliers are persisted alongside token prices. The existing 24-hour TTL and 15-minute failure retry remain; each network attempt is capped at 20 seconds.
- Cache and remote prices must be finite and non-negative, including long-context rates. Invalid thresholds are rejected without converting out-of-range doubles to integers.
- Each cost calculation uses one price-table snapshot, so a concurrent refresh cannot mix model resolution with prices from different snapshots.
- Verified GPT-5.6 and GPT-6 fallback rates carry `priority`/`fast` (2x) and `flex` (0.5x) tier prices. New models derive tiers from complete LiteLLM prices rather than a model-name list. A missing tier uses standard API-equivalent pricing; unverified explicit tiers make the cost partial. Provider-specific discounts and tool charges are not inferred from token logs.
- Codex rate polling checks the 16 most recently modified rollout files, with a directory rescan every 60 seconds. Changed files are scanned backwards up to 64 MB; unchanged files reuse parsed results. The newest valid main `codex` event wins. Snapshots expire after six hours based on event time (mtime only for old records without timestamps).
- JSONL readers stop at the file size captured for that refresh, retaining incomplete final lines for the next append. This prevents rereading concurrently appended bytes as new usage. Both readers retain their existing 64 MB per-file usage limit.

## Release checks

Run `swift test`, `make build`, and a clean `make release`. After the tag workflow completes, verify the downloaded ZIP, Developer ID signature, universal architecture, notarization ticket, Sparkle enclosure signature/build number, and Homebrew version/SHA256. Do not call local ad-hoc compilation a signed release.

If a release needs correction, publish a new build number; never move a published tag or lower Sparkle's build number. Older artifacts remain available from GitHub Releases for manual rollback.
