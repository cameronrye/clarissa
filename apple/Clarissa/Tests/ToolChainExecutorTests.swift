import Foundation
import Testing
@testable import ClarissaKit

// MARK: - Mock Tool Registry for Chain Tests

/// A minimal mock ToolRegistry that returns canned results for specific tool names.
/// Used to test ToolChainExecutor without hitting real tools.
@MainActor
private final class MockToolRegistryForChains {
    var results: [String: String] = [:]
    var shouldFail: Set<String> = []
    var executedTools: [(name: String, arguments: String)] = []
}

// MARK: - ToolChain Data Model Tests

@Suite("ToolChain Data Model Tests")
struct ToolChainDataModelTests {

    @Test("Built-in chains are non-empty and have valid structure")
    func testBuiltInChainsValid() {
        let builtIns = ToolChain.builtIn
        #expect(!builtIns.isEmpty)
        #expect(builtIns.count == 4)

        for chain in builtIns {
            #expect(!chain.id.isEmpty)
            #expect(!chain.name.isEmpty)
            #expect(!chain.description.isEmpty)
            #expect(!chain.icon.isEmpty)
            #expect(!chain.steps.isEmpty)
            #expect(chain.isBuiltIn == true)
        }
    }

    @Test("ToolChain Codable round-trip preserves all fields")
    func testToolChainCodable() throws {
        let chain = ToolChain(
            id: "test_chain",
            name: "Test Chain",
            description: "A test chain",
            icon: "star",
            steps: [
                ToolChainStep(
                    toolName: "calculator",
                    argumentTemplate: "{\"expression\": \"2+2\"}",
                    label: "Calculate something"
                ),
                ToolChainStep(
                    toolName: "remember",
                    argumentTemplate: "{\"content\": \"$0\"}",
                    label: "Save result",
                    isOptional: true
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 1000)
        )

        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(ToolChain.self, from: data)

        #expect(decoded.id == "test_chain")
        #expect(decoded.name == "Test Chain")
        #expect(decoded.description == "A test chain")
        #expect(decoded.icon == "star")
        #expect(decoded.steps.count == 2)
        #expect(decoded.steps[0].toolName == "calculator")
        #expect(decoded.steps[1].isOptional == true)
        #expect(decoded.isBuiltIn == false)
    }

    @Test("ToolChainStep defaults")
    func testToolChainStepDefaults() {
        let step = ToolChainStep(toolName: "weather", label: "Get weather")
        #expect(step.argumentTemplate == "{}")
        #expect(step.isOptional == false)
        #expect(!step.id.uuidString.isEmpty)
    }

    @Test("ChainStepStatus.isTerminal returns correct values")
    func testChainStepStatusIsTerminal() {
        #expect(ChainStepStatus.pending.isTerminal == false)
        #expect(ChainStepStatus.running.isTerminal == false)
        #expect(ChainStepStatus.completed(result: "ok").isTerminal == true)
        #expect(ChainStepStatus.skipped.isTerminal == true)
        #expect(ChainStepStatus.failed(error: "err").isTerminal == true)
    }
}

// MARK: - ToolChainResult Tests

@Suite("ToolChainResult Tests")
struct ToolChainResultTests {

    @Test("isSuccess returns true when all steps completed")
    func testIsSuccessAllCompleted() {
        let result = ToolChainResult(
            chainId: "test",
            stepResults: [
                StepResult(stepId: UUID(), toolName: "a", label: "A", status: .completed(result: "ok"), isOptional: false),
                StepResult(stepId: UUID(), toolName: "b", label: "B", status: .completed(result: "ok"), isOptional: false),
            ],
            duration: 1.0,
            wasAborted: false
        )
        #expect(result.isSuccess == true)
    }

    @Test("isSuccess returns true with skipped optional steps")
    func testIsSuccessWithSkippedOptional() {
        let result = ToolChainResult(
            chainId: "test",
            stepResults: [
                StepResult(stepId: UUID(), toolName: "a", label: "A", status: .completed(result: "ok"), isOptional: false),
                StepResult(stepId: UUID(), toolName: "b", label: "B", status: .skipped, isOptional: true),
            ],
            duration: 1.0,
            wasAborted: false
        )
        #expect(result.isSuccess == true)
    }

    @Test("isSuccess returns true with failed optional steps")
    func testIsSuccessWithFailedOptional() {
        let result = ToolChainResult(
            chainId: "test",
            stepResults: [
                StepResult(stepId: UUID(), toolName: "a", label: "A", status: .completed(result: "ok"), isOptional: false),
                StepResult(stepId: UUID(), toolName: "b", label: "B", status: .failed(error: "oops"), isOptional: true),
            ],
            duration: 1.0,
            wasAborted: false
        )
        #expect(result.isSuccess == true)
    }

    @Test("isSuccess returns false when aborted")
    func testIsSuccessReturnsFalseWhenAborted() {
        let result = ToolChainResult(
            chainId: "test",
            stepResults: [
                StepResult(stepId: UUID(), toolName: "a", label: "A", status: .completed(result: "ok"), isOptional: false),
                StepResult(stepId: UUID(), toolName: "b", label: "B", status: .failed(error: "crash"), isOptional: false),
            ],
            duration: 1.0,
            wasAborted: true
        )
        #expect(result.isSuccess == false)
    }

    @Test("isSuccess returns false when required step failed (not aborted)")
    func testIsSuccessReturnsFalseForRequiredFailure() {
        let result = ToolChainResult(
            chainId: "test",
            stepResults: [
                StepResult(stepId: UUID(), toolName: "a", label: "A", status: .failed(error: "err"), isOptional: false),
            ],
            duration: 1.0,
            wasAborted: false
        )
        #expect(result.isSuccess == false)
    }

    @Test("synthesisContext joins completed step results")
    func testSynthesisContext() {
        let result = ToolChainResult(
            chainId: "test",
            stepResults: [
                StepResult(stepId: UUID(), toolName: "a", label: "Weather", status: .completed(result: "Sunny 72F"), isOptional: false),
                StepResult(stepId: UUID(), toolName: "b", label: "Calendar", status: .completed(result: "Meeting at 2pm"), isOptional: false),
                StepResult(stepId: UUID(), toolName: "c", label: "Skipped", status: .skipped, isOptional: true),
            ],
            duration: 1.0,
            wasAborted: false
        )

        let context = result.synthesisContext
        #expect(context.contains("[Weather] Sunny 72F"))
        #expect(context.contains("[Calendar] Meeting at 2pm"))
        #expect(!context.contains("Skipped"))
    }

    @Test("Empty stepResults yields empty synthesisContext")
    func testEmptySynthesisContext() {
        let result = ToolChainResult(
            chainId: "test",
            stepResults: [],
            duration: 0,
            wasAborted: false
        )
        #expect(result.synthesisContext.isEmpty)
        #expect(result.isSuccess == true)
    }
}

// MARK: - Argument Resolution Tests (via Executor)

@Suite("ToolChainExecutor Argument Resolution Tests")
struct ToolChainArgumentTests {

    @Test("Executor resolves $input references in argument templates")
    @MainActor
    func testInputResolution() async throws {
        let chain = ToolChain(
            id: "test_input",
            name: "Input Test",
            description: "Tests $input",
            icon: "star",
            steps: [
                ToolChainStep(
                    toolName: "web_fetch",
                    argumentTemplate: "{\"url\":\"$input\"}",
                    label: "Fetch"
                ),
            ],
            createdAt: Date()
        )

        let executor = ToolChainExecutor(toolRegistry: .shared)

        // This will try to execute web_fetch with the resolved argument.
        // It will likely fail (no real URL), but we can verify the chain runs
        // and returns a result with the correct step count.
        let result = try await executor.execute(
            chain: chain,
            userInput: "https://example.com"
        )

        // Should have attempted one step
        #expect(result.stepResults.count == 1)
        #expect(result.stepResults[0].toolName == "web_fetch")
    }

    @Test("Executor handles chain with all steps skipped")
    @MainActor
    func testAllStepsSkipped() async throws {
        let step1Id = UUID()
        let step2Id = UUID()
        let chain = ToolChain(
            id: "test_skip",
            name: "Skip Test",
            description: "All skipped",
            icon: "star",
            steps: [
                ToolChainStep(id: step1Id, toolName: "weather", label: "Weather", isOptional: true),
                ToolChainStep(id: step2Id, toolName: "calendar", label: "Calendar", isOptional: true),
            ],
            createdAt: Date()
        )

        let executor = ToolChainExecutor(toolRegistry: .shared)
        let result = try await executor.execute(
            chain: chain,
            skippedStepIds: [step1Id, step2Id]
        )

        #expect(result.stepResults.count == 2)
        for step in result.stepResults {
            if case .skipped = step.status {
                // expected
            } else {
                Issue.record("Expected .skipped status but got \(step.status)")
            }
        }
        #expect(result.wasAborted == false)
        #expect(result.isSuccess == true)
    }

    @Test("Executor sets wasAborted when required step fails")
    @MainActor
    func testAbortOnRequiredFailure() async throws {
        let chain = ToolChain(
            id: "test_abort",
            name: "Abort Test",
            description: "Tests abort",
            icon: "star",
            steps: [
                ToolChainStep(toolName: "nonexistent_tool_xyz", label: "Will fail"),
                ToolChainStep(toolName: "calculator", argumentTemplate: "{\"expression\":\"1+1\"}", label: "Should not run"),
            ],
            createdAt: Date()
        )

        let executor = ToolChainExecutor(toolRegistry: .shared)
        let result = try await executor.execute(chain: chain)

        #expect(result.wasAborted == true)
        #expect(result.isSuccess == false)
        // Only one step should have a result (the failed one)
        #expect(result.stepResults.count == 1)
        if case .failed = result.stepResults[0].status {
            // expected
        } else {
            Issue.record("Expected .failed status")
        }
    }

    @Test("Executor continues past optional step failure")
    @MainActor
    func testContinuePastOptionalFailure() async throws {
        let chain = ToolChain(
            id: "test_optional",
            name: "Optional Test",
            description: "Tests optional skip",
            icon: "star",
            steps: [
                ToolChainStep(toolName: "nonexistent_tool_xyz", label: "Optional fail", isOptional: true),
                ToolChainStep(toolName: "calculator", argumentTemplate: "{\"expression\":\"1+1\"}", label: "Should run"),
            ],
            createdAt: Date()
        )

        let executor = ToolChainExecutor(toolRegistry: .shared)
        let result = try await executor.execute(chain: chain)

        #expect(result.wasAborted == false)
        #expect(result.stepResults.count == 2)

        // First step should be failed
        if case .failed = result.stepResults[0].status {
            // expected
        } else {
            Issue.record("Expected first step to be .failed")
        }

        // Second step should be completed
        if case .completed = result.stepResults[1].status {
            // expected
        } else {
            Issue.record("Expected second step to be .completed")
        }

        // isSuccess should be true because the failed step is optional
        #expect(result.isSuccess == true)
    }

    @Test("Calculator tool executes successfully through chain")
    @MainActor
    func testCalculatorChainExecution() async throws {
        let chain = ToolChain(
            id: "test_calc",
            name: "Calc Test",
            description: "Tests calculator",
            icon: "star",
            steps: [
                ToolChainStep(
                    toolName: "calculator",
                    argumentTemplate: "{\"expression\":\"2+2\"}",
                    label: "Calculate"
                ),
            ],
            createdAt: Date()
        )

        let executor = ToolChainExecutor(toolRegistry: .shared)
        let result = try await executor.execute(chain: chain)

        #expect(result.wasAborted == false)
        #expect(result.isSuccess == true)
        #expect(result.stepResults.count == 1)

        if case .completed(let output) = result.stepResults[0].status {
            #expect(output.contains("4"))
        } else {
            Issue.record("Expected .completed status with result containing 4")
        }
    }
}
