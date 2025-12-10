import Foundation
import Testing
@testable import ClarissaKit

@Suite("Clarissa Tests")
struct ClarissaTests {

    @Test("Message creation")
    func testMessageCreation() {
        let userMessage = Message.user("Hello")
        #expect(userMessage.role == .user)
        #expect(userMessage.content == "Hello")

        let assistantMessage = Message.assistant("Hi there!")
        #expect(assistantMessage.role == .assistant)
        #expect(assistantMessage.content == "Hi there!")

        let systemMessage = Message.system("You are helpful")
        #expect(systemMessage.role == .system)
    }

    @Test("Tool call creation")
    func testToolCallCreation() {
        let toolCall = ToolCall(name: "calculator", arguments: "{\"expression\": \"2+2\"}")
        #expect(toolCall.name == "calculator")
        #expect(!toolCall.id.isEmpty)
    }

    @Test("Tool message creation")
    func testToolMessage() {
        let toolMessage = Message.tool(callId: "123", name: "calculator", content: "{\"result\": 4}")
        #expect(toolMessage.role == .tool)
        #expect(toolMessage.toolCallId == "123")
        #expect(toolMessage.toolName == "calculator")
    }

    @Test("Message with tool calls")
    func testMessageWithToolCalls() {
        let toolCall = ToolCall(name: "calendar", arguments: "{\"action\": \"list\"}")
        let message = Message.assistant("Let me check your calendar", toolCalls: [toolCall])
        #expect(message.role == .assistant)
        #expect(message.toolCalls?.count == 1)
        #expect(message.toolCalls?.first?.name == "calendar")
    }

    @Test("Agent config defaults")
    func testAgentConfigDefaults() {
        let config = AgentConfig()
        #expect(config.maxIterations == 10)
        #expect(config.autoApprove == false)
    }

    @Test("Agent config custom values")
    func testAgentConfigCustom() {
        let config = AgentConfig(maxIterations: 5, autoApprove: true)
        #expect(config.maxIterations == 5)
        #expect(config.autoApprove == true)
    }

    @Test("LLM provider type identifiable")
    func testLLMProviderType() {
        let foundationModels = LLMProviderType.foundationModels
        let openRouter = LLMProviderType.openRouter

        #expect(foundationModels.id == foundationModels.rawValue)
        #expect(openRouter.id == openRouter.rawValue)
        #expect(LLMProviderType.allCases.count == 2)
    }
}

@Suite("Tool Tests")
struct ToolTests {

    @Test("Calculator tool execution")
    func testCalculatorTool() async throws {
        let calculator = CalculatorTool()
        #expect(calculator.name == "calculator")
        #expect(calculator.requiresConfirmation == false)

        let result = try await calculator.execute(arguments: "{\"expression\": \"2 + 2\"}")
        #expect(result.contains("4"))
    }

    @Test("Calculator tool invalid expression throws")
    func testCalculatorInvalidExpression() async {
        let calculator = CalculatorTool()
        await #expect(throws: ToolError.self) {
            _ = try await calculator.execute(arguments: "{\"expression\": \"invalid\"}")
        }
    }

    @Test("Remember tool properties")
    func testRememberToolProperties() {
        let rememberTool = RememberTool()
        #expect(rememberTool.name == "remember")
        #expect(rememberTool.requiresConfirmation == false)
        #expect(rememberTool.priority == .core)
    }

    @Test("Tool registry contains expected tools")
    @MainActor
    func testToolRegistry() {
        let registry = ToolRegistry.shared
        let names = registry.getToolNames()

        #expect(names.contains("calculator"))
        #expect(names.contains("calendar"))
        #expect(names.contains("contacts"))
        #expect(names.contains("web_fetch"))
        #expect(names.contains("remember"))
        #expect(names.contains("reminders"))
        #expect(names.contains("location"))
    }

    @Test("Tool definitions have required fields")
    @MainActor
    func testToolDefinitions() {
        let registry = ToolRegistry.shared
        let definitions = registry.getDefinitions()

        for definition in definitions {
            #expect(!definition.name.isEmpty)
            #expect(!definition.description.isEmpty)
        }
    }

    @Test("Calculator handles math functions")
    func testCalculatorMathFunctions() async throws {
        let calculator = CalculatorTool()

        // Test sqrt
        let sqrtResult = try await calculator.execute(arguments: "{\"expression\": \"sqrt(16)\"}")
        #expect(sqrtResult.contains("4"))

        // Test PI constant
        let piResult = try await calculator.execute(arguments: "{\"expression\": \"PI\"}")
        #expect(piResult.contains("3.14"))

        // Test exponentiation
        let powResult = try await calculator.execute(arguments: "{\"expression\": \"2^3\"}")
        #expect(powResult.contains("8"))
    }

    @Test("Calculator validates input")
    func testCalculatorValidation() async {
        let calculator = CalculatorTool()

        // Empty expression should fail
        await #expect(throws: ToolError.self) {
            _ = try await calculator.execute(arguments: "{\"expression\": \"\"}")
        }

        // Unbalanced parentheses should fail
        await #expect(throws: ToolError.self) {
            _ = try await calculator.execute(arguments: "{\"expression\": \"(2+3\"}")
        }
    }

    @Test("Reminders tool properties")
    func testRemindersToolProperties() {
        let remindersTool = RemindersTool()
        #expect(remindersTool.name == "reminders")
        #expect(remindersTool.requiresConfirmation == true)
        #expect(remindersTool.priority == .extended)
    }

    @Test("Location tool properties")
    func testLocationToolProperties() {
        let locationTool = LocationTool()
        #expect(locationTool.name == "location")
        #expect(locationTool.requiresConfirmation == true)
        #expect(locationTool.priority == .extended)
    }
}

@Suite("Keychain Tests")
struct KeychainTests {

    @Test("Keychain set and get")
    func testKeychainSetGet() throws {
        let keychain = KeychainManager.shared
        let testKey = "test_key_\(UUID().uuidString)"
        let testValue = "test_value_123"

        // Set value
        try keychain.set(testValue, forKey: testKey)

        // Get value
        let retrieved = keychain.get(key: testKey)
        #expect(retrieved == testValue)

        // Clean up
        try keychain.delete(key: testKey)
        #expect(keychain.get(key: testKey) == nil)
    }

    @Test("Keychain exists check")
    func testKeychainExists() throws {
        let keychain = KeychainManager.shared
        let testKey = "exists_test_\(UUID().uuidString)"

        #expect(keychain.exists(key: testKey) == false)

        try keychain.set("value", forKey: testKey)
        #expect(keychain.exists(key: testKey) == true)

        try keychain.delete(key: testKey)
        #expect(keychain.exists(key: testKey) == false)
    }
}

@Suite("Session Tests")
struct SessionTests {

    @Test("Session creation")
    func testSessionCreation() {
        let session = Session()
        #expect(session.title == "New Conversation")
        #expect(session.messages.isEmpty)
    }

    @Test("Session title generation")
    func testSessionTitleGeneration() {
        var session = Session()
        session.messages = [Message.user("Hello, how are you today?")]
        session.generateTitle()

        #expect(session.title.contains("Hello"))
        #expect(!session.title.contains("\n"))
    }

    @Test("Session title truncation")
    func testSessionTitleTruncation() {
        var session = Session()
        let longMessage = String(repeating: "a", count: 100)
        session.messages = [Message.user(longMessage)]
        session.generateTitle()

        #expect(session.title.count <= 53) // 50 chars + "..."
        #expect(session.title.hasSuffix("..."))
    }
}

@Suite("Memory Tests")
struct MemoryTests {

    @Test("Memory creation")
    func testMemoryCreation() {
        let memory = Memory(content: "User prefers dark mode")
        #expect(memory.content == "User prefers dark mode")
        #expect(memory.createdAt <= Date())
    }
}

