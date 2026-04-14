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
