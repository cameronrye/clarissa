import Foundation
import Testing
@testable import ClarissaKit

// Note: WatchMessage and related types are in Sources/Watch which is excluded from the package
// These tests cover the message encoding/decoding logic that would be shared

@Suite("Watch Message Tests")
struct WatchMessageTests {
    
    // MARK: - QueryRequest Tests
    
    @Test("QueryRequest creation has unique ID")
    func testQueryRequestUniqueId() {
        let request1 = WatchQueryRequest(text: "Hello")
        let request2 = WatchQueryRequest(text: "Hello")
        #expect(request1.id != request2.id)
    }
    
    @Test("QueryRequest stores text correctly")
    func testQueryRequestText() {
        let request = WatchQueryRequest(text: "What's the weather?")
        #expect(request.text == "What's the weather?")
    }
    
    @Test("QueryRequest has timestamp")
    func testQueryRequestTimestamp() {
        let before = Date()
        let request = WatchQueryRequest(text: "Test")
        let after = Date()
        
        #expect(request.timestamp >= before)
        #expect(request.timestamp <= after)
    }
    
    @Test("QueryRequest is Codable")
    func testQueryRequestCodable() throws {
        let original = WatchQueryRequest(text: "Encode me")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchQueryRequest.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.text == original.text)
        #expect(decoded.timestamp == original.timestamp)
    }
    
    // MARK: - QueryResponse Tests
    
    @Test("QueryResponse stores response text")
    func testQueryResponseText() {
        let requestId = UUID()
        let response = WatchQueryResponse(requestId: requestId, text: "The weather is sunny")
        
        #expect(response.requestId == requestId)
        #expect(response.text == "The weather is sunny")
    }
    
    @Test("QueryResponse has timestamp")
    func testQueryResponseTimestamp() {
        let response = WatchQueryResponse(requestId: UUID(), text: "Test")
        #expect(response.timestamp <= Date())
    }
    
    @Test("QueryResponse is Codable")
    func testQueryResponseCodable() throws {
        let requestId = UUID()
        let original = WatchQueryResponse(requestId: requestId, text: "Response text")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchQueryResponse.self, from: data)
        
        #expect(decoded.requestId == original.requestId)
        #expect(decoded.text == original.text)
    }
    
    // MARK: - ProcessingStatus Tests
    
    @Test("ProcessingStatus statuses")
    func testProcessingStatusStatuses() {
        let requestId = UUID()
        
        let received = WatchProcessingStatus(requestId: requestId, status: .received)
        #expect(received.status == .received)
        
        let thinking = WatchProcessingStatus(requestId: requestId, status: .thinking)
        #expect(thinking.status == .thinking)
        
        let usingTool = WatchProcessingStatus(requestId: requestId, status: .usingTool)
        #expect(usingTool.status == .usingTool)
        
        let processing = WatchProcessingStatus(requestId: requestId, status: .processing)
        #expect(processing.status == .processing)
        
        let completed = WatchProcessingStatus(requestId: requestId, status: .completed)
        #expect(completed.status == .completed)
    }
    
    @Test("ProcessingStatus is Codable")
    func testProcessingStatusCodable() throws {
        let original = WatchProcessingStatus(requestId: UUID(), status: .thinking)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchProcessingStatus.self, from: data)
        
        #expect(decoded.requestId == original.requestId)
        #expect(decoded.status == original.status)
    }
    
    // MARK: - ErrorInfo Tests
    
    @Test("ErrorInfo with request ID")
    func testErrorInfoWithRequestId() {
        let requestId = UUID()
        let error = WatchErrorInfo(requestId: requestId, message: "Something went wrong", isRecoverable: true)
        
        #expect(error.requestId == requestId)
        #expect(error.message == "Something went wrong")
        #expect(error.isRecoverable == true)
    }
    
    @Test("ErrorInfo without request ID")
    func testErrorInfoWithoutRequestId() {
        let error = WatchErrorInfo(requestId: nil, message: "Connection lost", isRecoverable: false)
        
        #expect(error.requestId == nil)
        #expect(error.message == "Connection lost")
        #expect(error.isRecoverable == false)
    }
    
    @Test("ErrorInfo is Codable")
    func testErrorInfoCodable() throws {
        let original = WatchErrorInfo(requestId: UUID(), message: "Test error", isRecoverable: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchErrorInfo.self, from: data)
        
        #expect(decoded.requestId == original.requestId)
        #expect(decoded.message == original.message)
        #expect(decoded.isRecoverable == original.isRecoverable)
    }
}

