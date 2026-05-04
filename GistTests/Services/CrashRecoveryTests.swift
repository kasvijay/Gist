import XCTest
@testable import Gist

final class CrashRecoveryTests: XCTestCase {
    private var tempDir: URL!

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GistCrashRecoveryTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createSessionFolder(_ session: Session, hasWAV: Bool = false, hasPartialTranscript: Bool = false) {
        let folder = tempDir.appendingPathComponent(session.folderName)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let data = try! encoder.encode(session)
        try! data.write(to: folder.appendingPathComponent("metadata.json"))

        if hasWAV {
            // Create a minimal valid WAV file
            var wavData = Data()
            wavData.append("RIFF".data(using: .ascii)!)
            wavData.append(Data(repeating: 0, count: 4))
            wavData.append("WAVE".data(using: .ascii)!)
            wavData.append("fmt ".data(using: .ascii)!)
            var fmtSize: UInt32 = 16
            wavData.append(Data(bytes: &fmtSize, count: 4))
            wavData.append(Data(repeating: 0, count: 16))
            wavData.append("data".data(using: .ascii)!)
            wavData.append(Data(repeating: 0, count: 4))
            wavData.append(Data(repeating: 0, count: 100))
            try! wavData.write(to: folder.appendingPathComponent("audio.wav"))
        }

        if hasPartialTranscript {
            let partial = "{}".data(using: .utf8)!
            try! partial.write(to: folder.appendingPathComponent("transcript.partial.json"))
        }
    }

    // MARK: - Recovery

    func testRecoverSessionWithRecordingStatus() {
        let session = Session(id: "crashed-session", name: "Crashed", startedAt: Date(), status: .recording)
        createSessionFolder(session, hasWAV: true)

        let result = CrashRecovery.recoverSessions(in: tempDir)

        XCTAssertEqual(result.recoveredIDs, ["crashed-session"])
        XCTAssertEqual(result.pendingConversions.count, 1)
        XCTAssertEqual(result.pendingConversions[0].sessionID, "crashed-session")

        // Verify metadata was updated to .recovered
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metaURL = tempDir.appendingPathComponent("crashed-session/metadata.json")
        let recovered = try! decoder.decode(Session.self, from: Data(contentsOf: metaURL))
        XCTAssertEqual(recovered.status, .recovered)
        XCTAssertNotNil(recovered.endedAt)
    }

    func testRecoverSessionSetsEndedAt() {
        let session = Session(id: "no-end", name: "No End", startedAt: Date(), endedAt: nil, status: .recording)
        createSessionFolder(session, hasWAV: true)

        _ = CrashRecovery.recoverSessions(in: tempDir)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metaURL = tempDir.appendingPathComponent("no-end/metadata.json")
        let recovered = try! decoder.decode(Session.self, from: Data(contentsOf: metaURL))
        XCTAssertNotNil(recovered.endedAt)
    }

    func testIgnoresCompleteSession() {
        let session = Session(id: "complete-session", name: "Done", startedAt: Date(), status: .complete)
        createSessionFolder(session)

        let result = CrashRecovery.recoverSessions(in: tempDir)

        XCTAssertTrue(result.recoveredIDs.isEmpty)
        XCTAssertTrue(result.pendingConversions.isEmpty)
    }

    func testRenamesPartialTranscript() {
        let session = Session(id: "partial-session", name: "Partial", startedAt: Date(), status: .recording)
        createSessionFolder(session, hasWAV: true, hasPartialTranscript: true)

        _ = CrashRecovery.recoverSessions(in: tempDir)

        let folder = tempDir.appendingPathComponent("partial-session")
        let transcriptExists = FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("transcript.json").path
        )
        let partialGone = !FileManager.default.fileExists(
            atPath: folder.appendingPathComponent("transcript.partial.json").path
        )
        XCTAssertTrue(transcriptExists, "transcript.json should exist after recovery")
        XCTAssertTrue(partialGone, "transcript.partial.json should be renamed")
    }

    func testHandlesCorruptMetadataGracefully() {
        // Create a folder with invalid metadata
        let folder = tempDir.appendingPathComponent("corrupt-session")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! "not valid json".data(using: .utf8)!.write(to: folder.appendingPathComponent("metadata.json"))

        let result = CrashRecovery.recoverSessions(in: tempDir)
        // Should not crash, just skip the corrupt folder
        XCTAssertTrue(result.recoveredIDs.isEmpty)
    }

    func testEmptyDirectoryReturnsEmptyResult() {
        let result = CrashRecovery.recoverSessions(in: tempDir)
        XCTAssertTrue(result.recoveredIDs.isEmpty)
        XCTAssertTrue(result.pendingConversions.isEmpty)
    }
}
