import Foundation
import Testing
@testable import ClarissaKit

@Suite("Agent Integration Tests")
struct AgentIntegrationTests {

    // MARK: - Helpers

    /// Create a configured Agent with a mock provider and callbacks.
    /// Returns the agent and callbacks so tests can inspect captured events.
    @MainActor
    private static func makeAgent(
        config: AgentConfig = AgentConfig(),
        responses: [String],
        toolCalls: [[ToolCall]] = []
    ) -> (Agent, MockLLMProvider, MockAgentCallbacks) {
        let provider = MockLLMProvider(responses: responses, toolCalls: toolCalls)
        let callbacks = MockAgentCallbacks()
        let agent = Agent(config: config)
        agent.setProvider(provider)
        agent.callbacks = callbacks
        return (agent, provider, callbacks)
    }

    // MARK: - Test 1: Tool Execution ReAct Cycle

    @Test("Tool execution ReAct cycle completes with correct callbacks")
    @MainActor
    func testToolExecutionReActCycle() async throws {
        // Configure: first response triggers a calculator tool call,
        // second response delivers the final answer.
        let calculatorCall = ToolCall(name: "calculator", arguments: "{\"expression\": \"2+2\"}")
        let (agent, provider, callbacks) = Self.makeAgent(
            responses: ["", "The answer is 4"],
            toolCalls: [[calculatorCall], []]
        )

        let response = try await agent.run("What is 2+2?")

        // The agent should have called the provider twice (tool call + final answer)
        #expect(provider.messagesReceived.count == 2)

        // Final response should contain the expected text
        #expect(response.contains("The answer is 4"))

        // Callback verification:
        // onThinking should have been called once per iteration (2 iterations)
        #expect(callbacks.thinkingCount == 2)

        // One tool call was made
        #expect(callbacks.toolCalls.count == 1)
        #expect(callbacks.toolCalls.first?.name == "calculator")

        // One tool result was received (calculator is a real registered tool, should succeed)
        #expect(callbacks.toolResults.count == 1)
        #expect(callbacks.toolResults.first?.success == true)

        // Final response callback fired once
        #expect(callbacks.responses.count == 1)
        #expect(callbacks.responses.first?.contains("The answer is 4") == true)
    }

    // MARK: - Test 2: Tool Failure Handling

    @Test("Tool failure is reported back to the model and handled gracefully")
    @MainActor
    func testToolFailureHandling() async throws {
        // Request a tool that does not exist in the registry
        let badToolCall = ToolCall(name: "nonexistent_tool", arguments: "{}")
        let (agent, _, callbacks) = Self.makeAgent(
            responses: ["", "Sorry, I couldn't find that tool"],
            toolCalls: [[badToolCall], []]
        )

        let response = try await agent.run("Use the nonexistent tool")

        // The agent should gracefully recover with the fallback response
        #expect(response.contains("Sorry, I couldn't find that tool"))

        // The tool call was attempted
        #expect(callbacks.toolCalls.count == 1)
        #expect(callbacks.toolCalls.first?.name == "nonexistent_tool")

        // The tool result should indicate failure (success == false)
        #expect(callbacks.toolResults.count == 1)
        #expect(callbacks.toolResults.first?.success == false)

        // The error result should have been fed back to the model, which then
        // provided the fallback response
        #expect(callbacks.responses.count == 1)
    }

    // MARK: - Test 3: Max Iterations Enforcement

    @Test("Agent throws maxIterationsReached when loop limit is exceeded")
    @MainActor
    func testMaxIterationsEnforcement() async throws {
        // Configure agent with maxIterations = 2 and a provider that always
        // returns tool calls, forcing the loop to never settle on a final answer.
        let toolCall = ToolCall(name: "calculator", arguments: "{\"expression\": \"1+1\"}")
        let (agent, _, _) = Self.makeAgent(
            config: AgentConfig(maxIterations: 2),
            responses: ["", "", ""],
            toolCalls: [[toolCall], [toolCall], [toolCall]]
        )

        await #expect(throws: AgentError.self) {
            _ = try await agent.run("Keep calling tools forever")
        }
    }

    // MARK: - Test 4: Context Trimming Verification

    @Test("Agent handles large message history without crashing")
    @MainActor
    func testContextTrimmingWithManyMessages() async throws {
        let (agent, _, _) = Self.makeAgent(
            responses: ["I'm still here!"]
        )

        // Load many messages into the agent by running repeated queries.
        // Each run adds user + assistant messages to history, eventually
        // triggering context trimming.
        for i in 0..<20 {
            let longMessage = String(repeating: "This is message number \(i). ", count: 50)
            _ = try await agent.run(longMessage)
        }

        // Run one final query and verify the agent produces a coherent response
        let finalResponse = try await agent.run("Are you still working?")
        #expect(!finalResponse.isEmpty)

        // Verify context stats are reasonable — the agent should not have
        // accumulated unbounded history
        let stats = agent.getContextStats()
        #expect(stats.messageCount > 0)
        #expect(stats.usagePercent <= 1.0)
    }

    // MARK: - Test 5: Analytics Recording

    @Test("Analytics collector records a completed session after agent run")
    @MainActor
    func testAnalyticsRecording() async throws {
        // Reset analytics so we start from a known state
        await AnalyticsCollector.shared.reset()

        let (agent, _, _) = Self.makeAgent(
            responses: ["Analytics test response"]
        )

        _ = try await agent.run("Test analytics")

        // After a successful run, totalSessions should have increased
        let metrics = await AnalyticsCollector.shared.getAggregateMetrics()
        #expect(metrics.totalSessions > 0)
    }

    // MARK: - Test 6: Simple Question (No Tools)

    @Test("Simple question without tools returns in a single iteration")
    @MainActor
    func testSimpleQuestionNoTools() async throws {
        let (agent, provider, callbacks) = Self.makeAgent(
            responses: ["Hello!"]
        )

        let response = try await agent.run("Hi there")

        // Response should match
        #expect(response == "Hello!")

        // Only one call to the provider (single iteration, no tool calls)
        #expect(provider.messagesReceived.count == 1)

        // onThinking called exactly once
        #expect(callbacks.thinkingCount == 1)

        // No tool calls or tool results
        #expect(callbacks.toolCalls.isEmpty)
        #expect(callbacks.toolResults.isEmpty)

        // Final response callback fired once
        #expect(callbacks.responses.count == 1)
        #expect(callbacks.responses.first == "Hello!")
    }
}
