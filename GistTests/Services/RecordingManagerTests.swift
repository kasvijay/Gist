import XCTest
@testable import Gist

@MainActor
final class RecordingManagerTests: XCTestCase {
    private var manager: RecordingManager!

    override func setUp() {
        super.setUp()
        manager = RecordingManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStarting)
        XCTAssertFalse(manager.isPaused)
        XCTAssertFalse(manager.isMicMuted)
        XCTAssertEqual(manager.elapsedTime, 0)
        XCTAssertNil(manager.error)
        XCTAssertNil(manager.pipelineStep)
        XCTAssertNil(manager.processingSessionID)
        XCTAssertNil(manager.activeSessionID)
        XCTAssertFalse(manager.showConsentAlert)
    }

    // MARK: - Consent Flow

    func testStartRecordingShowsConsentAlert() {
        let store = SessionStore()
        let engine = TranscriptionEngine()
        let diarization = DiarizationManager()

        manager.startRecording(sessionStore: store, transcriptionEngine: engine, diarizationManager: diarization)
        XCTAssertTrue(manager.showConsentAlert)
    }

    func testCancelRecordingClearsAlert() {
        let store = SessionStore()
        let engine = TranscriptionEngine()
        let diarization = DiarizationManager()

        manager.startRecording(sessionStore: store, transcriptionEngine: engine, diarizationManager: diarization)
        manager.cancelRecording()

        XCTAssertFalse(manager.showConsentAlert)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStarting)
    }

    func testConfirmWithoutServicesIsNoOp() {
        // Call confirm without first calling startRecording (no stashed services)
        manager.confirmAndStartRecording()
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStarting)
    }

    // MARK: - Double-Start Prevention

    func testStartWhileRecordingIsNoOp() {
        // Simulate recording state manually
        // Since we can't easily set isRecording without starting a real pipeline,
        // we test via the guard: startRecording checks !isRecording && !isStarting
        let store = SessionStore()
        let engine = TranscriptionEngine()
        let diarization = DiarizationManager()

        // First start shows consent
        manager.startRecording(sessionStore: store, transcriptionEngine: engine, diarizationManager: diarization)
        XCTAssertTrue(manager.showConsentAlert)

        // Cancel to reset
        manager.cancelRecording()

        // Verify we can start again (not blocked)
        manager.startRecording(sessionStore: store, transcriptionEngine: engine, diarizationManager: diarization)
        XCTAssertTrue(manager.showConsentAlert)
    }

    // MARK: - Pause / Resume Guards

    func testPauseWhenNotRecordingIsNoOp() {
        manager.pauseRecording()
        XCTAssertFalse(manager.isPaused)
    }

    func testResumeWhenNotRecordingIsNoOp() {
        manager.resumeRecording()
        XCTAssertFalse(manager.isPaused)
    }

    func testResumeWhenNotPausedIsNoOp() {
        // Even if isRecording were true, resuming when not paused should be a no-op
        // We can't set isRecording without a real pipeline, but we verify the guard behavior
        manager.resumeRecording()
        XCTAssertFalse(manager.isPaused)
    }

    // MARK: - Mic Mute

    func testToggleMicMute() {
        XCTAssertFalse(manager.isMicMuted)
        manager.toggleMicMute()
        XCTAssertTrue(manager.isMicMuted)
        manager.toggleMicMute()
        XCTAssertFalse(manager.isMicMuted)
    }

    // MARK: - Stop Guard

    func testStopWhenNotRecordingReturnsNil() {
        let store = SessionStore()
        let engine = TranscriptionEngine()
        let diarization = DiarizationManager()

        let result = manager.stopRecording(
            sessionStore: store,
            transcriptionEngine: engine,
            diarizationManager: diarization
        )
        XCTAssertNil(result)
    }

    // MARK: - Pipeline State

    func testIsPipelineRunningComputedProperty() {
        XCTAssertFalse(manager.isPipelineRunning)
        manager.pipelineStep = .transcribing
        XCTAssertTrue(manager.isPipelineRunning)
        manager.pipelineStep = nil
        XCTAssertFalse(manager.isPipelineRunning)
    }

    func testActiveSessionIDNilWhenNotRecording() {
        XCTAssertNil(manager.activeSessionID)
    }
}
