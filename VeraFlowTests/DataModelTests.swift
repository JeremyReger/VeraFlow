import Testing
import Foundation
@testable import VeraFlow

@Suite("Data Model & Type Tests")
struct DataModelTests {
    @Test("PipelineStage transitions and display titles")
    func testPipelineStage() {
        let recordingStage = PipelineStage.recording
        #expect(!recordingStage.isTerminal)
        #expect(recordingStage.displayTitle == "Recording...")
        
        let readyStage = PipelineStage.ready
        #expect(readyStage.isTerminal)
        #expect(readyStage.displayTitle == "Ready")
        
        let failedStage = PipelineStage.failed
        #expect(failedStage.isTerminal)
        #expect(failedStage.displayTitle == "Failed")
    }
    
    @Test("TimedWord initialization and encoding")
    func testTimedWord() throws {
        let word = TimedWord(text: "VeraFlow", start: 1.0, end: 1.5)
        #expect(word.text == "VeraFlow")
        #expect(word.start == 1.0)
        #expect(word.end == 1.5)
        
        let data = try JSONEncoder().encode([word])
        let decoded = try JSONDecoder().decode([TimedWord].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded.first?.text == "VeraFlow")
    }
    
    @Test("ActionItem encoding and properties")
    func testActionItem() throws {
        let action = ActionItem(
            task: "Verify on-device models",
            owner: "Alex",
            speakerKey: "S2",
            dueText: "tomorrow",
            resolvedDueDate: Date(),
            timestamp: "02:14",
            audioTime: 134.0,
            isCompleted: false
        )
        
        #expect(action.task == "Verify on-device models")
        #expect(action.speakerKey == "S2")
        #expect(!action.isCompleted)
        
        let data = try JSONEncoder().encode([action])
        let decoded = try JSONDecoder().decode([ActionItem].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded.first?.task == "Verify on-device models")
    }
    
    @Test("AppConstants branding alignment")
    func testAppConstants() {
        #expect(AppConstants.appName == "VeraFlow")
        #expect(AppConstants.alphaCodename == "Riffle")
        #expect(AppConstants.productionBundleID == "com.veraflow.app")
        #expect(AppConstants.alphaBundleID == "com.veraflow.riffle")
        #expect(AppConstants.lifetimeUnlockProductID == "veraflow.unlock.lifetime")
    }
}
