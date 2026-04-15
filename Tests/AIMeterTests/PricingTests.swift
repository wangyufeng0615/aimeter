import XCTest
@testable import AIMeter

final class PricingTests: XCTestCase {
    func testModelFamilyKeepsGPT54VariantsSeparate() {
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4"), "gpt-5.4")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-mini"), "gpt-5.4-mini")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-pro"), "gpt-5.4-pro")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-nano"), "gpt-5.4-nano")
    }

    func testModelFamilyPrefersCurrentClaudePricingKeys() {
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-6"), "claude-opus-4-6")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-1"), "claude-opus-4-1")
        XCTAssertEqual(Pricing.modelFamily("claude-sonnet-4-6"), "claude-sonnet-4-6")
        XCTAssertEqual(Pricing.modelFamily("claude-haiku-4-5"), "claude-haiku-4-5")
    }

    func testTieredBelowThresholdUsesBasePriceOnly() {
        // 100k tokens with a configured tier stays on base price
        let cost = Pricing.tiered(100_000, base: 1e-6, tier: 2e-6)
        XCTAssertEqual(cost, 0.1, accuracy: 1e-12)
    }

    func testTieredExactlyAtThresholdUsesBasePriceOnly() {
        // Exactly at 200k — condition is `> tieredThreshold`, so still base
        let cost = Pricing.tiered(Pricing.tieredThreshold, base: 1e-6, tier: 2e-6)
        XCTAssertEqual(cost, 0.2, accuracy: 1e-12)
    }

    func testTieredJustAboveThresholdSplitsPriceCorrectly() {
        // 200_001 → first 200k at base, 1 token at tier
        let cost = Pricing.tiered(Pricing.tieredThreshold + 1, base: 1e-6, tier: 2e-6)
        let expected = Double(Pricing.tieredThreshold) * 1e-6 + 1 * 2e-6
        XCTAssertEqual(cost, expected, accuracy: 1e-12)
    }

    func testTieredFarAboveThresholdSplitsPriceCorrectly() {
        // 500k → 200k base + 300k tier
        let cost = Pricing.tiered(500_000, base: 1e-6, tier: 2e-6)
        let expected = Double(Pricing.tieredThreshold) * 1e-6
                     + Double(500_000 - Pricing.tieredThreshold) * 2e-6
        XCTAssertEqual(cost, expected, accuracy: 1e-12)
    }

    func testTieredWithNilTierAlwaysUsesBase() {
        // No tier configured → 500k tokens at base
        let cost = Pricing.tiered(500_000, base: 1e-6, tier: nil)
        XCTAssertEqual(cost, 0.5, accuracy: 1e-12)
    }

    func testTieredNonPositiveTokensReturnsZero() {
        XCTAssertEqual(Pricing.tiered(0, base: 1e-6, tier: 2e-6), 0)
        XCTAssertEqual(Pricing.tiered(-1, base: 1e-6, tier: 2e-6), 0)
        XCTAssertEqual(Pricing.tiered(-100_000, base: 1e-6, tier: nil), 0)
    }

    func testParseLiteLLMDoesNotLetProOrLegacyOverwriteBaseModels() {
        let parsed = Pricing.parseLiteLLM([
            "gpt-5.4-pro": [
                "input_cost_per_token": 30e-6,
                "output_cost_per_token": 180e-6,
                "cache_read_input_token_cost": 3e-6,
            ],
            "gpt-5.4": [
                "input_cost_per_token": 2.5e-6,
                "output_cost_per_token": 15e-6,
                "cache_read_input_token_cost": 0.25e-6,
            ],
            "gpt-5.4-mini": [
                "input_cost_per_token": 0.75e-6,
                "output_cost_per_token": 4.5e-6,
                "cache_read_input_token_cost": 0.075e-6,
            ],
            "claude-opus-4-1": [
                "input_cost_per_token": 15e-6,
                "output_cost_per_token": 75e-6,
                "cache_creation_input_token_cost": 18.75e-6,
                "cache_read_input_token_cost": 1.5e-6,
            ],
            "claude-opus-4-6": [
                "input_cost_per_token": 5e-6,
                "output_cost_per_token": 25e-6,
                "cache_creation_input_token_cost": 6.25e-6,
                "cache_read_input_token_cost": 0.5e-6,
            ],
        ])

        XCTAssertEqual(parsed["gpt-5.4"]?.input, 2.5e-6)
        XCTAssertEqual(parsed["gpt-5.4-pro"]?.input, 30e-6)
        XCTAssertEqual(parsed["gpt-5.4-mini"]?.input, 0.75e-6)
        XCTAssertEqual(parsed["claude-opus-4-6"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-4-1"]?.input, 15e-6)
    }
}
