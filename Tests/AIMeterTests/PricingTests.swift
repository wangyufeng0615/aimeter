import XCTest
@testable import AIMeter

final class PricingTests: XCTestCase {
    func testModelFamilyKeepsGPT54VariantsSeparate() {
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4"), "gpt-5.4")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-mini"), "gpt-5.4-mini")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-pro"), "gpt-5.4-pro")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-nano"), "gpt-5.4-nano")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.5"), "gpt-5.5")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.5-pro"), "gpt-5.5-pro")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6"), "gpt-5.6-sol")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-sol"), "gpt-5.6-sol")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-terra"), "gpt-5.6-terra")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-luna"), "gpt-5.6-luna")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-sol-pro"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.7"), "unknown")
    }

    func testModelFamilyPrefersCurrentClaudePricingKeys() {
        XCTAssertEqual(Pricing.modelFamily("claude-fable-5"), "claude-fable-5")
        XCTAssertEqual(Pricing.modelFamily("fable-5"), "claude-fable-5")
        XCTAssertEqual(Pricing.modelFamily("claude-mythos-5"), "claude-mythos-5")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-8"), "claude-opus-4-8")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-7-20260416"), "claude-opus-4-7")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-6"), "claude-opus-4-6")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-1"), "claude-opus-4-1")
        XCTAssertEqual(Pricing.modelFamily("claude-sonnet-5"), "claude-sonnet-5")
        XCTAssertEqual(Pricing.modelFamily("claude-sonnet-4-6"), "claude-sonnet-4-6")
        XCTAssertEqual(Pricing.modelFamily("claude-haiku-4-5"), "claude-haiku-4-5")
        XCTAssertEqual(Pricing.modelFamily("claude-sonnet-6"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("model_api/experimental_0630"), "unknown")
    }

    func testFablePricingIncludesOneHourCacheWrites() {
        let cost = Pricing.cost(
            model: "claude-fable-5",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )

        XCTAssertEqual(cost, 93.5, accuracy: 1e-12)
    }

    func testOpusPricingIncludesFastMode() {
        let standard48 = Pricing.cost(
            model: "claude-opus-4-8",
            speed: "standard",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )
        let fast48 = Pricing.cost(
            model: "claude-opus-4-8",
            speed: "fast",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )
        let fast47 = Pricing.cost(
            model: "claude-opus-4-7",
            speed: "fast",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )

        XCTAssertEqual(standard48, 46.75, accuracy: 1e-12)
        XCTAssertEqual(fast48, 93.5, accuracy: 1e-12)
        XCTAssertEqual(fast47, 280.5, accuracy: 1e-12)
    }

    func testRetiredOpus46FastModeUsesStandardPricing() {
        let cost = Pricing.cost(
            model: "claude-opus-4-6",
            speed: "fast",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )

        XCTAssertEqual(cost, 46.75, accuracy: 1e-12)
    }

    func testSonnet5UsesCurrentCalendarPricing() {
        let cost = Pricing.cost(
            model: "claude-sonnet-5",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let standardPricingStart = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 1
        ))!
        let expected = Date() < standardPricingStart ? 18.7 : 28.05
        XCTAssertEqual(cost, expected, accuracy: 1e-12)
    }

    func testClaudeUSInferenceAppliesDataResidencyMultiplier() {
        let cost = Pricing.cost(
            model: "claude-fable-5",
            inferenceGeo: "us",
            input: 1_000_000,
            output: 0,
            cacheWrite: 0,
            cacheRead: 0
        )

        XCTAssertEqual(cost, 11, accuracy: 1e-12)
    }

    func testGPT55LongContextPricingStartsAbove272KAndAppliesToFullRequest() {
        let atThreshold = Pricing.cost(
            model: "gpt-5.5",
            input: 272_000,
            output: 1,
            cacheWrite: 0,
            cacheRead: 0
        )
        let aboveThreshold = Pricing.cost(
            model: "gpt-5.5",
            input: 272_001,
            output: 1,
            cacheWrite: 0,
            cacheRead: 0
        )

        XCTAssertEqual(atThreshold, 1.36 + 30e-6, accuracy: 1e-12)
        XCTAssertEqual(aboveThreshold, 2.72001 + 45e-6, accuracy: 1e-12)
    }

    func testGPT55ProDoesNotDiscountCachedInput() {
        let cost = Pricing.cost(
            model: "gpt-5.5-pro",
            input: 0,
            output: 0,
            cacheWrite: 0,
            cacheRead: 100_000
        )

        XCTAssertEqual(cost, 3, accuracy: 1e-12)
        XCTAssertEqual(
            Pricing.cost(
                model: "gpt-5.5-pro",
                input: 0,
                output: 0,
                cacheWrite: 0,
                cacheRead: 1_000_000
            ),
            30,
            accuracy: 1e-12
        )
    }

    func testUnknownModelHasNoInventedFallbackPrice() {
        XCTAssertFalse(Pricing.hasRate(model: "model_api/experimental_0630"))
        XCTAssertEqual(
            Pricing.cost(
                model: "model_api/experimental_0630",
                input: 1_000_000,
                output: 1_000_000,
                cacheWrite: 0,
                cacheRead: 0
            ),
            0
        )
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
            "gpt-5.5": [
                "input_cost_per_token": 5e-6,
                "output_cost_per_token": 30e-6,
                "cache_read_input_token_cost": 0.5e-6,
            ],
            "gpt-5.5-pro": [
                "input_cost_per_token": 30e-6,
                "output_cost_per_token": 180e-6,
                "cache_read_input_token_cost": 3e-6,
            ],
            "gpt-5.6": [
                "input_cost_per_token": 5e-6,
                "output_cost_per_token": 30e-6,
                "cache_read_input_token_cost": 0.5e-6,
                "cache_creation_input_token_cost": 6.25e-6,
                "input_cost_per_token_above_272k_tokens": 10e-6,
                "output_cost_per_token_above_272k_tokens": 45e-6,
            ],
            "anthropic.claude-fable-5": [
                "input_cost_per_token": 10e-6,
                "output_cost_per_token": 50e-6,
                "cache_creation_input_token_cost": 12.5e-6,
                "cache_read_input_token_cost": 1e-6,
            ],
            "claude-fable-5": [
                "input_cost_per_token": 10e-6,
                "output_cost_per_token": 50e-6,
                "cache_creation_input_token_cost": 12.5e-6,
                "cache_creation_input_token_cost_above_1hr": 20e-6,
                "cache_read_input_token_cost": 1e-6,
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
            "anthropic.claude-opus-4-7": [
                "input_cost_per_token": 5e-6,
                "output_cost_per_token": 25e-6,
                "cache_creation_input_token_cost": 6.25e-6,
                "cache_creation_input_token_cost_above_1hr": 10e-6,
                "cache_read_input_token_cost": 0.5e-6,
            ],
            "claude-opus-4-8": [
                "input_cost_per_token": 5e-6,
                "output_cost_per_token": 25e-6,
                "cache_creation_input_token_cost": 6.25e-6,
                "cache_creation_input_token_cost_above_1hr": 10e-6,
                "cache_read_input_token_cost": 0.5e-6,
            ],
            "claude-sonnet-5": [
                "input_cost_per_token": 2e-6,
                "output_cost_per_token": 10e-6,
                "cache_creation_input_token_cost": 2.5e-6,
                "cache_creation_input_token_cost_above_1hr": 4e-6,
                "cache_read_input_token_cost": 0.2e-6,
            ],
        ])

        XCTAssertEqual(parsed["gpt-5.4"]?.input, 2.5e-6)
        XCTAssertEqual(parsed["gpt-5.4-pro"]?.input, 30e-6)
        XCTAssertEqual(parsed["gpt-5.4-mini"]?.input, 0.75e-6)
        XCTAssertEqual(parsed["gpt-5.5"]?.input, 5e-6)
        XCTAssertEqual(parsed["gpt-5.5-pro"]?.input, 30e-6)
        XCTAssertEqual(parsed["gpt-5.5-pro"]?.cacheRead, 30e-6)
        XCTAssertNil(parsed["gpt-5.5-pro"]?.longContextThreshold)
        XCTAssertEqual(parsed["gpt-5.6-sol"]?.input, 5e-6)
        XCTAssertEqual(parsed["gpt-5.6-sol"]?.cacheWrite, 6.25e-6)
        XCTAssertEqual(parsed["gpt-5.6-sol"]?.longContextThreshold, 272_000)
        XCTAssertEqual(parsed["claude-fable-5"]?.input, 10e-6)
        XCTAssertEqual(parsed["claude-fable-5"]?.output, 50e-6)
        XCTAssertEqual(parsed["claude-fable-5"]?.cacheWrite, 12.5e-6)
        XCTAssertEqual(parsed["claude-fable-5"]?.cacheWrite1h, 20e-6)
        XCTAssertEqual(parsed["claude-fable-5"]?.cacheRead, 1e-6)
        XCTAssertEqual(parsed["claude-opus-4-8"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-4-8"]?.cacheWrite1h, 10e-6)
        XCTAssertEqual(parsed["claude-opus-4-7"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-4-7"]?.cacheWrite1h, 10e-6)
        XCTAssertEqual(parsed["claude-opus-4-6"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-4-1"]?.input, 15e-6)
        XCTAssertEqual(parsed["claude-sonnet-5"]?.input, 2e-6)
    }
}
