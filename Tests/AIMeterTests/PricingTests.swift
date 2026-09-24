import XCTest
@testable import AIMeter

final class PricingTests: XCTestCase {
    func testSeptemberModelsResolveAndHaveOfflineRates() {
        for model in ["claude-fable-5-1", "claude-mythos-5-1", "claude-opus-5-5",
                      "gpt-6-astra", "gpt-6-sol", "gpt-6-luna"] {
            XCTAssertEqual(Pricing.modelFamily(model), model)
            XCTAssertTrue(Pricing.hasRate(model: model))
        }
        XCTAssertEqual(Pricing.modelFamily("fable-5-1"), "claude-fable-5-1")
        XCTAssertEqual(Pricing.modelFamily("openai/gpt-6-astra-20260903"), "gpt-6-astra")
        XCTAssertEqual(Pricing.modelFamily("openai/gpt-6-sol-20260922"), "gpt-6-sol")
        XCTAssertEqual(Pricing.modelFamily("gpt-6-luna-20260922"), "gpt-6-luna")
        XCTAssertEqual(Pricing.modelFamily("opus-5-5"), "claude-opus-5-5")
        XCTAssertEqual(Pricing.modelFamily("gpt-6-astra-pro"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("gpt-6-sol-pro"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("gpt-6-luna-pro"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("relay/gpt-6-astra"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("relay/gpt-6-sol"), "unknown")
        XCTAssertEqual(Pricing.cost(model: "claude-fable-5-1", input: 0, output: 0,
                                    cacheWrite: 0, cacheRead: 1_000_000), 0.25, accuracy: 1e-12)
        XCTAssertEqual(Pricing.cost(model: "claude-fable-5", input: 0, output: 0,
                                    cacheWrite: 0, cacheRead: 1_000_000), 1, accuracy: 1e-12)
    }

    func testMinorClaudeVersionsCannotOverwriteExistingFamilies() {
        let price: [String: Any] = ["input_cost_per_token": 10e-6, "output_cost_per_token": 50e-6,
            "cache_read_input_token_cost": 0.25e-6, "cache_creation_input_token_cost": 12.5e-6,
            "cache_creation_input_token_cost_above_1hr": 20e-6]
        let parsed = Pricing.parseLiteLLM([
            "claude-fable-5-1": price, "claude-mythos-5-1": price,
            "claude-sonnet-5-1": price, "claude-opus-5-1": price,
            "us.anthropic.claude-fable-5-1": price, "relay/claude-fable-5-2": price,
            "anthropic.claude-fable-5-2": price
        ])
        XCTAssertEqual(Set(parsed.keys), Set(["claude-fable-5-1", "claude-mythos-5-1",
                                              "claude-sonnet-5-1", "claude-opus-5-1", "claude-fable-5-2"]))
        XCTAssertEqual(parsed["claude-fable-5-1"]?.cacheRead, 0.25e-6)
        XCTAssertTrue(Pricing.parseLiteLLM(["us.anthropic.claude-fable-5": price]).isEmpty)
    }

    func testAstraFullRequestThresholdAndServiceTier() {
        let normal = Pricing.cost(model: "gpt-6-astra", input: 72_000, output: 100,
                                  cacheWrite: 100_000, cacheRead: 100_000)
        let long = Pricing.cost(model: "gpt-6-astra", input: 72_001, output: 100,
                                cacheWrite: 100_000, cacheRead: 100_000)
        XCTAssertEqual(normal, 0.72 + 0.005 + 1.25 + 0.1, accuracy: 1e-12)
        XCTAssertEqual(long, 1.44002 + 0.0075 + 2.5 + 0.2, accuracy: 1e-12)
        XCTAssertEqual(Pricing.cost(model: "gpt-6-astra", serviceTier: "priority",
                                    input: 72_001, output: 100, cacheWrite: 100_000, cacheRead: 100_000),
                       2 * long, accuracy: 1e-12)
        XCTAssertEqual(Pricing.cost(model: "gpt-6-astra", serviceTier: "flex",
                                    input: 72_001, output: 100, cacheWrite: 100_000, cacheRead: 100_000),
                       0.5 * long, accuracy: 1e-12)
        XCTAssertFalse(Pricing.hasRate(model: "gpt-6-astra", serviceTier: "unverified"))
    }

    func testGPT6SolAndLunaOfficialTokenPricesAndTiers() {
        for (model, standard, longContext) in [
            ("gpt-6-sol", 0.435, 1.108004),
            ("gpt-6-luna", 0.02175, 0.0554002)
        ] {
            let short = Pricing.cost(model: model, input: 100_000, output: 10_000,
                                     cacheWrite: 50_000, cacheRead: 50_000)
            XCTAssertEqual(short, standard, accuracy: 1e-12)
            XCTAssertEqual(Pricing.cost(model: model, serviceTier: "fast", input: 100_000,
                                        output: 10_000, cacheWrite: 50_000, cacheRead: 50_000),
                           2 * standard, accuracy: 1e-12)
            XCTAssertEqual(Pricing.cost(model: model, serviceTier: "flex", input: 100_000,
                                        output: 10_000, cacheWrite: 50_000, cacheRead: 50_000),
                           0.5 * standard, accuracy: 1e-12)
            XCTAssertEqual(Pricing.cost(model: model, input: 172_001, output: 10_000,
                                        cacheWrite: 50_000, cacheRead: 50_000),
                           longContext, accuracy: 1e-12)
            XCTAssertFalse(Pricing.hasRate(model: model, serviceTier: "unverified"))
        }
    }

    func testNewGPT6ModelsAcceptOnlyVerifiedLiteLLMKeys() {
        let sol: [String: Any] = ["input_cost_per_token": 2e-6,
                                  "output_cost_per_token": 10e-6,
                                  "cache_read_input_token_cost": 0.2e-6,
                                  "cache_creation_input_token_cost": 2.5e-6]
        let luna: [String: Any] = ["input_cost_per_token": 0.1e-6,
                                   "output_cost_per_token": 0.5e-6,
                                   "cache_read_input_token_cost": 0.01e-6,
                                   "cache_creation_input_token_cost": 0.125e-6]
        let incompletePro: [String: Any] = ["input_cost_per_token": 2e-6,
                                             "output_cost_per_token": 10e-6]
        let parsed = Pricing.parseLiteLLM([
            "gpt-6-sol": sol, "gpt-6-luna": luna,
            "gpt-6-sol-pro": incompletePro, "openrouter/openai/gpt-6-sol": sol
        ])
        XCTAssertEqual(Set(parsed.keys), Set(["gpt-6-sol", "gpt-6-luna"]))
        XCTAssertEqual(parsed["gpt-6-sol"]?.longContextThreshold, 272_000)
        XCTAssertEqual(parsed["gpt-6-luna"]?.input, 0.1e-6)
    }

    func testNewDirectGPTModelNeedsCompleteIndependentPricing() {
        let complete: [String: Any] = [
            "input_cost_per_token": 2e-6, "output_cost_per_token": 10e-6,
            "cache_read_input_token_cost": 0.2e-6,
            "cache_creation_input_token_cost": 2.5e-6,
            "input_cost_per_token_above_272k_tokens": 4e-6,
            "output_cost_per_token_above_272k_tokens": 15e-6,
            "cache_read_input_token_cost_above_272k_tokens": 0.4e-6,
            "cache_creation_input_token_cost_above_272k_tokens": 5e-6
        ]
        var missingCache = complete
        missingCache.removeValue(forKey: "cache_read_input_token_cost")
        var missingLongPrice = complete
        missingLongPrice.removeValue(forKey: "output_cost_per_token_above_272k_tokens")
        var mixedLongSchedule = complete
        mixedLongSchedule["input_cost_per_token_above_200k_tokens"] = 3e-6
        var wrongProvider = complete
        wrongProvider["litellm_provider"] = "openrouter"
        let parsed = Pricing.parseLiteLLM([
            "gpt-7-nova": complete,
            "gpt-7-nova-pro": missingCache,
            "gpt-7-nova-mini": missingLongPrice,
            "gpt-7-nova-mixed": mixedLongSchedule,
            "gpt-7-nova-other-provider": wrongProvider,
            "openrouter/openai/gpt-7-nova": complete
        ])
        XCTAssertEqual(Set(parsed.keys), Set(["gpt-7-nova"]))
        XCTAssertEqual(parsed["gpt-7-nova"]?.longContextThreshold, 272_000)

        let families = Set(parsed.keys)
        XCTAssertEqual(Pricing.modelFamily("gpt-7-nova", availableFamilies: families), "gpt-7-nova")
        XCTAssertEqual(Pricing.modelFamily("openai/gpt-7-nova", availableFamilies: families), "gpt-7-nova")
        XCTAssertEqual(Pricing.modelFamily("gpt-7-nova-20260923", availableFamilies: families), "gpt-7-nova")
        XCTAssertEqual(Pricing.modelFamily("gpt-7-nova-pro", availableFamilies: families), "unknown")
        XCTAssertEqual(Pricing.modelFamily("relay/gpt-7-nova", availableFamilies: families), "unknown")

        var independentProPrice = complete
        independentProPrice["input_cost_per_token"] = 30e-6
        let separatelyPriced = Pricing.parseLiteLLM(["gpt-7-nova": complete,
                                                      "gpt-7-nova-pro": independentProPrice])
        XCTAssertEqual(separatelyPriced["gpt-7-nova-pro"]?.input, 30e-6)
        XCTAssertEqual(Pricing.modelFamily("gpt-7-nova-pro",
                                           availableFamilies: Set(separatelyPriced.keys)),
                       "gpt-7-nova-pro")
    }

    func testFutureFlatGPTAndDatedPriceKeyNeedNoModelList() {
        let flat: [String: Any] = [
            "input_cost_per_token": 1e-6, "output_cost_per_token": 5e-6,
            "cache_read_input_token_cost": 0.1e-6,
            "cache_creation_input_token_cost": 1.25e-6
        ]
        let parsed = Pricing.parseLiteLLM(["gpt-7-mini-20270115": flat])
        XCTAssertEqual(Set(parsed.keys), Set(["gpt-7-mini"]))
        XCTAssertNil(parsed["gpt-7-mini"]?.longContextThreshold)
        XCTAssertEqual(Pricing.modelFamily("gpt-7-mini", availableFamilies: Set(parsed.keys)),
                       "gpt-7-mini")
        XCTAssertEqual(Pricing.modelFamily("gpt-7-mini-20270115", availableFamilies: Set(parsed.keys)),
                       "gpt-7-mini")
    }

    func testFutureGPTServiceTiersRequireCompleteUniformPrices() {
        let fields = ["input_cost_per_token", "output_cost_per_token",
                      "cache_read_input_token_cost", "cache_creation_input_token_cost"]
        let normal = [2e-6, 10e-6, 0.2e-6, 2.5e-6]
        let long = [4e-6, 15e-6, 0.4e-6, 5e-6]
        var complete: [String: Any] = [:]
        for (index, field) in fields.enumerated() {
            complete[field] = normal[index]
            complete["\(field)_above_272k_tokens"] = long[index]
            complete["\(field)_priority"] = normal[index] * 2
            complete["\(field)_above_272k_tokens_priority"] = long[index] * 2
            complete["\(field)_flex"] = normal[index] * 0.5
            complete["\(field)_above_272k_tokens_flex"] = long[index] * 0.5
        }
        let fullyPriced = Pricing.parseLiteLLM(["gpt-7-nova": complete])
        XCTAssertEqual(fullyPriced["gpt-7-nova"]?.fastMultiplier, 2)
        XCTAssertEqual(fullyPriced["gpt-7-nova"]?.flexMultiplier, 0.5)

        var partial = complete
        partial.removeValue(forKey: "cache_creation_input_token_cost_above_272k_tokens_priority")
        let partialPrice = Pricing.parseLiteLLM(["gpt-7-nova": partial])
        XCTAssertNotNil(partialPrice["gpt-7-nova"])
        XCTAssertNil(partialPrice["gpt-7-nova"]?.fastMultiplier)
        XCTAssertEqual(partialPrice["gpt-7-nova"]?.flexMultiplier, 0.5)

        var nonUniform = complete
        nonUniform["output_cost_per_token_priority"] = 25e-6
        XCTAssertNil(Pricing.parseLiteLLM(["gpt-7-nova": nonUniform])["gpt-7-nova"]?.fastMultiplier)
    }

    func testDynamicGPTCacheRequiresTheSameLongContextContract() {
        let complete: [String: Double] = [
            "input": 2e-6, "output": 10e-6, "cacheRead": 0.2e-6, "cacheWrite": 2.5e-6,
            "inputTiered": 4e-6, "outputTiered": 15e-6,
            "cacheReadTiered": 0.4e-6, "cacheWriteTiered": 5e-6,
            "longContextThreshold": 272_000
        ]
        var incomplete = complete
        incomplete.removeValue(forKey: "cacheWriteTiered")
        let flat: [String: Double] = [
            "input": 1e-6, "output": 5e-6,
            "cacheRead": 0.1e-6, "cacheWrite": 1.25e-6,
            "fastMultiplier": 2
        ]
        var invalidTier = flat
        invalidTier["fastMultiplier"] = -1
        let parsed = Pricing.parseCacheRates([
            "gpt-7-nova": complete, "gpt-7-nova-mini": incomplete,
            "gpt-7-flat": flat, "gpt-7-invalid": invalidTier,
            "relay/gpt-7-nova": complete
        ])
        XCTAssertEqual(Set(parsed.keys), Set(["gpt-7-nova", "gpt-7-flat"]))
        XCTAssertEqual(parsed["gpt-7-flat"]?.fastMultiplier, 2)
        XCTAssertEqual(Pricing.parseCacheRates(["gpt-6-sol": complete])["gpt-6-sol"]?.fastMultiplier, 2)
    }

    func testGPT56DefaultsAndSolHistoricalPromotionBoundary() {
        for (model, input, output) in [("gpt-5.6-sol", 4.0, 20.0), ("gpt-5.6-terra", 2.0, 12.0),
                                        ("gpt-5.6-luna", 0.2, 1.2)] {
            XCTAssertEqual(Pricing.cost(model: model, at: utcDate(2026, 9, 6), input: 100_000,
                                        output: 100_000, cacheWrite: 0, cacheRead: 0),
                           (input + output) / 10, accuracy: 1e-12)
        }
        XCTAssertEqual(Pricing.cost(model: "gpt-5.6", at: utcDate(2026, 8, 20), input: 100_000,
                                    output: 100_000, cacheWrite: 0, cacheRead: 0), 3.5, accuracy: 1e-12)
        XCTAssertEqual(Pricing.cost(model: "gpt-5.6", at: utcDate(2026, 8, 21), input: 100_000,
                                    output: 100_000, cacheWrite: 0, cacheRead: 0), 2.4, accuracy: 1e-12)
    }

    func testPricingRejectsInvalidPremiumsAndCorruptCacheThresholds() {
        for value in [Double.nan, Double.infinity, -1, 1e100] {
            XCTAssertTrue(Pricing.parseLiteLLM(["gpt-6-astra": [
                "input_cost_per_token": 10e-6, "output_cost_per_token": 50e-6,
                "input_cost_per_token_above_272k_tokens": value]]).isEmpty)
            XCTAssertTrue(Pricing.parseCacheRates(["gpt-6-astra": [
                "input": 10e-6, "output": 50e-6, "cacheRead": 1e-6, "cacheWrite": 12.5e-6,
                "longContextThreshold": value]]).isEmpty)
        }
        let corrected = Pricing.parseCacheRates(["claude-sonnet-5": [
            "input": 3e-6, "output": 15e-6, "cacheRead": 0.3e-6, "cacheWrite": 3.75e-6]])
        XCTAssertEqual(corrected["claude-sonnet-5"]?.input, 2e-6)
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testModelFamilyKeepsGPT54VariantsSeparate() {
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4"), "gpt-5.4")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-mini"), "gpt-5.4-mini")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-pro"), "gpt-5.4-pro")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.4-nano"), "gpt-5.4-nano")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.5"), "gpt-5.5")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.5-pro"), "gpt-5.5-pro")
        XCTAssertFalse(Pricing.hasRate(model: "gpt-5.4-pro", serviceTier: "fast"))
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6"), "gpt-5.6-sol")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-sol"), "gpt-5.6-sol")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-terra"), "gpt-5.6-terra")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-luna"), "gpt-5.6-luna")
        XCTAssertEqual(Pricing.modelFamily("gpt-6-sol"), "gpt-6-sol")
        XCTAssertEqual(Pricing.modelFamily("gpt-6-luna"), "gpt-6-luna")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.6-sol-pro"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("gpt-5.7"), "unknown")
    }

    func testModelFamilyPrefersCurrentClaudePricingKeys() {
        XCTAssertEqual(Pricing.modelFamily("claude-fable-5"), "claude-fable-5")
        XCTAssertEqual(Pricing.modelFamily("fable-5"), "claude-fable-5")
        XCTAssertEqual(Pricing.modelFamily("claude-mythos-5"), "claude-mythos-5")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-5"), "claude-opus-5")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-5-5"), "claude-opus-5-5")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-5-5-20260922"), "claude-opus-5-5")
        XCTAssertEqual(Pricing.modelFamily("opus-5"), "claude-opus-5")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-5-20260723"), "claude-opus-5")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-8"), "claude-opus-4-8")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-7-20260416"), "claude-opus-4-7")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-6"), "claude-opus-4-6")
        XCTAssertEqual(Pricing.modelFamily("claude-opus-4-1"), "claude-opus-4-1")
        XCTAssertEqual(Pricing.modelFamily("claude-sonnet-5"), "claude-sonnet-5")
        XCTAssertEqual(Pricing.modelFamily("claude-sonnet-4-6"), "claude-sonnet-4-6")
        XCTAssertEqual(Pricing.modelFamily("claude-haiku-4-5"), "claude-haiku-4-5")
        XCTAssertEqual(Pricing.modelFamily("claude-sonnet-6"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("model_api/experimental_0630"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("relay/claude-opus-5"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("model_api/gpt-5.6-sol"), "unknown")
        XCTAssertEqual(Pricing.modelFamily("openai/gpt-5.6-sol"), "gpt-5.6-sol")
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
        let standard5 = Pricing.cost(
            model: "claude-opus-5",
            speed: "standard",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )
        let fast5 = Pricing.cost(
            model: "claude-opus-5",
            speed: "fast",
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )
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

        XCTAssertEqual(standard5, 46.75, accuracy: 1e-12)
        XCTAssertEqual(fast5, 93.5, accuracy: 1e-12)
        XCTAssertEqual(standard48, 46.75, accuracy: 1e-12)
        XCTAssertEqual(fast48, 93.5, accuracy: 1e-12)
        XCTAssertEqual(fast47, 0, accuracy: 1e-12)
        XCTAssertFalse(Pricing.hasRate(model: "claude-opus-4-7", speed: "fast"))
    }

    func testOpus55OfficialCachePricesAndFastMode() {
        let standard = Pricing.cost(model: "claude-opus-5-5", input: 100_000, output: 100_000,
                                    cacheWrite: 100_000, cacheWrite1h: 100_000, cacheRead: 100_000)
        let fast = Pricing.cost(model: "claude-opus-5-5", speed: "fast", input: 100_000,
                                output: 100_000, cacheWrite: 100_000, cacheWrite1h: 100_000,
                                cacheRead: 100_000)
        XCTAssertEqual(standard, 3.72, accuracy: 1e-12)
        XCTAssertEqual(fast, 7.44, accuracy: 1e-12)
        XCTAssertTrue(Pricing.hasRate(model: "claude-opus-5-5", speed: "fast"))
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

    func testSonnet5CancelledSeptemberIncreaseKeepsPermanentPrice() {
        let introductoryCost = Pricing.cost(
            model: "claude-sonnet-5",
            at: utcDate(2026, 8, 31),
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )
        let standardCost = Pricing.cost(
            model: "claude-sonnet-5",
            at: utcDate(2026, 9, 1),
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000
        )

        XCTAssertEqual(introductoryCost, 18.7, accuracy: 1e-12)
        XCTAssertEqual(standardCost, 18.7, accuracy: 1e-12)
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
        XCTAssertTrue(Pricing.supportsUSInference(family: "claude-sonnet-6"))
        XCTAssertTrue(Pricing.supportsUSInference(family: "claude-opus-4-6"))
        XCTAssertFalse(Pricing.supportsUSInference(family: "claude-haiku-4-5"))
    }

    func testPricingRefreshPolicyRechecksStaleCacheAndBacksOffAfterFailure() {
        XCTAssertFalse(Pricing.shouldRefreshPricing(
            cacheAge: 60,
            secondsSinceLastAttempt: nil
        ))
        XCTAssertTrue(Pricing.shouldRefreshPricing(
            cacheAge: 24 * 60 * 60,
            secondsSinceLastAttempt: nil
        ))
        XCTAssertFalse(Pricing.shouldRefreshPricing(
            cacheAge: nil,
            secondsSinceLastAttempt: 14 * 60
        ))
        XCTAssertTrue(Pricing.shouldRefreshPricing(
            cacheAge: nil,
            secondsSinceLastAttempt: 15 * 60
        ))
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
                "cache_read_input_token_cost_above_272k_tokens": 1e-6,
                "cache_creation_input_token_cost_above_272k_tokens": 12.5e-6,
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
            "claude-opus-5": [
                "input_cost_per_token": 5e-6,
                "output_cost_per_token": 25e-6,
                "cache_creation_input_token_cost": 6.25e-6,
                "cache_creation_input_token_cost_above_1hr": 10e-6,
                "cache_read_input_token_cost": 0.5e-6,
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
        XCTAssertEqual(parsed["claude-opus-5"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-5"]?.cacheWrite1h, 10e-6)
        XCTAssertEqual(parsed["claude-opus-4-8"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-4-8"]?.cacheWrite1h, 10e-6)
        XCTAssertEqual(parsed["claude-opus-4-7"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-4-7"]?.cacheWrite1h, 10e-6)
        XCTAssertEqual(parsed["claude-opus-4-6"]?.input, 5e-6)
        XCTAssertEqual(parsed["claude-opus-4-1"]?.input, 15e-6)
        XCTAssertEqual(parsed["claude-sonnet-5"]?.input, 2e-6)
    }

    func testParseLiteLLMAcceptsFutureDirectClaudeVersionWithoutNewWhitelistEntry() {
        let parsed = Pricing.parseLiteLLM([
            "claude-sonnet-6-20270115": [
                "input_cost_per_token": 4e-6,
                "output_cost_per_token": 20e-6,
                "cache_creation_input_token_cost": 5e-6,
                "cache_creation_input_token_cost_above_1hr": 8e-6,
                "cache_read_input_token_cost": 0.4e-6,
            ],
            "claude-unverified-6": [
                "input_cost_per_token": 1e-6,
                "output_cost_per_token": 2e-6,
            ],
        ])

        XCTAssertEqual(parsed["claude-sonnet-6"]?.input, 4e-6)
        XCTAssertEqual(parsed["claude-sonnet-6"]?.output, 20e-6)
        XCTAssertNil(parsed["claude-unverified-6"])
        XCTAssertEqual(
            Pricing.modelFamily(
                "claude-sonnet-6-20270115",
                availableFamilies: Set(parsed.keys)
            ),
            "claude-sonnet-6"
        )
    }

    func testFutureClaudeFastRateUsesIndependentDirectPrice() {
        let base: [String: Any] = [
            "input_cost_per_token": 4e-6, "output_cost_per_token": 20e-6,
            "cache_read_input_token_cost": 0.4e-6,
            "cache_creation_input_token_cost": 5e-6,
            "cache_creation_input_token_cost_above_1hr": 8e-6
        ]
        let fast: [String: Any] = [
            "input_cost_per_token": 8e-6, "output_cost_per_token": 40e-6,
            "cache_read_input_token_cost": 0.8e-6,
            "cache_creation_input_token_cost": 10e-6,
            "cache_creation_input_token_cost_above_1hr": 16e-6
        ]
        let parsed = Pricing.parseLiteLLM([
            "claude-opus-6-20270115": base,
            "claude-opus-6-fast-20270115": fast,
            "relay/claude-opus-6-fast": fast
        ])
        XCTAssertEqual(parsed["claude-opus-6"]?.input, 4e-6)
        XCTAssertEqual(parsed["claude-opus-6-fast"]?.input, 8e-6)
        XCTAssertEqual(Set(parsed.keys), Set(["claude-opus-6", "claude-opus-6-fast"]))

        var incompleteFast = fast
        incompleteFast.removeValue(forKey: "cache_creation_input_token_cost_above_1hr")
        XCTAssertNil(Pricing.parseLiteLLM(["claude-opus-6-fast": incompleteFast])["claude-opus-6-fast"])
    }

    func testFutureClaudeProductFamilyNeedsNoNameList() {
        let price: [String: Any] = [
            "input_cost_per_token": 3e-6, "output_cost_per_token": 15e-6,
            "cache_read_input_token_cost": 0.3e-6,
            "cache_creation_input_token_cost": 3.75e-6,
            "cache_creation_input_token_cost_above_1hr": 6e-6,
            "litellm_provider": "anthropic"
        ]
        let parsed = Pricing.parseLiteLLM(["claude-aurora-6-20270115": price])
        XCTAssertEqual(parsed["claude-aurora-6"]?.input, 3e-6)
        XCTAssertEqual(Pricing.modelFamily("aurora-6", availableFamilies: Set(parsed.keys)),
                       "claude-aurora-6")
        XCTAssertTrue(Pricing.supportsUSInference(family: "claude-aurora-6"))
        var wrongProvider = price
        wrongProvider["litellm_provider"] = "openrouter"
        XCTAssertNil(Pricing.parseLiteLLM(["claude-aurora-6": wrongProvider])["claude-aurora-6"])
    }

    func testParseLiteLLMRejectsFutureClaudeRateWithIncompleteCacheContract() {
        let parsed = Pricing.parseLiteLLM([
            "claude-sonnet-6-20270115": [
                "input_cost_per_token": 4e-6,
                "output_cost_per_token": 20e-6,
                "cache_read_input_token_cost": 0.4e-6,
            ],
        ])

        XCTAssertNil(parsed["claude-sonnet-6"])
    }
}
