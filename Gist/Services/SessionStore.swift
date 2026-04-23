import Foundation
import AVFoundation
import os

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [SessionIndex.SessionEntry] = []
    @Published var currentSession: Session?

    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "SessionStore")
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Serial queue for all disk I/O — keeps writes off the main thread.
    private nonisolated static let ioQueue = DispatchQueue(label: "com.vijaykas.gist.sessionstore.io", qos: .utility)
    private static let ioLogger = Logger(subsystem: "com.vijaykas.gist", category: "SessionStore.IO")

    /// Encode and write a Codable value to disk on the background I/O queue.
    private nonisolated static func writeInBackground<T: Encodable & Sendable>(_ value: T, to url: URL) {
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(value)
                try data.write(to: url, options: .atomic)
            } catch {
                ioLogger.error("Background write failed for \(url.lastPathComponent): \(error)")
            }
        }
    }

    var baseURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("Gist")
    }

    private(set) var pendingRecoveryConversions: [(wav: URL, m4a: URL, sessionID: String)] = []

    init() {
        ensureBaseDirectory()
        let result = CrashRecovery.recoverSessions(in: baseURL)
        if !result.recoveredIDs.isEmpty {
            logger.info("Recovered \(result.recoveredIDs.count) interrupted sessions")
        }
        pendingRecoveryConversions = result.pendingConversions
        loadIndex()
    }

    private func ensureBaseDirectory() {
        if !fileManager.fileExists(atPath: baseURL.path) {
            do {
                try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
                logger.info("Created ~/Transcripts/")
            } catch {
                logger.error("Failed to create Transcripts dir: \(error)")
            }
        }
    }

    // MARK: - Session Lifecycle

    func startSession() -> Session {
        let now = Date()
        let id = Session.makeID(date: now)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        let name = formatter.string(from: now)
        let session = Session(
            id: id,
            name: name,
            startedAt: now,
            status: .recording,
            devices: Session.Devices(microphone: "Default Microphone")
        )

        // Create session folder
        let folderURL = baseURL.appendingPathComponent(session.folderName)
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create session folder: \(error)")
        }

        // Write initial metadata
        writeMetadata(session)
        currentSession = session
        return session
    }

    func finishSession(duration: TimeInterval) {
        guard var session = currentSession else { return }
        session.endedAt = Date()
        session.durationSeconds = duration
        session.status = .complete

        writeMetadata(session)
        updateIndex(session: session)
        currentSession = nil
    }

    // MARK: - File Paths

    func sessionFolderURL(for session: Session) -> URL {
        baseURL.appendingPathComponent(session.folderName)
    }

    /// URL for the compressed M4A audio file (final storage format).
    func audioFileURL(for session: Session) -> URL {
        sessionFolderURL(for: session).appendingPathComponent("audio.m4a")
    }

    /// URL for the WAV file used during recording (crash-safe format).
    func recordingAudioFileURL(for session: Session) -> URL {
        sessionFolderURL(for: session).appendingPathComponent("audio.wav")
    }

    /// Returns the best available audio file URL — prefers M4A, falls back to WAV.
    func bestAudioFileURL(for session: Session) -> URL {
        let m4a = audioFileURL(for: session)
        if fileManager.fileExists(atPath: m4a.path) { return m4a }
        let wav = recordingAudioFileURL(for: session)
        if fileManager.fileExists(atPath: wav.path) { return wav }
        return m4a
    }

    func metadataURL(for session: Session) -> URL {
        sessionFolderURL(for: session).appendingPathComponent("metadata.json")
    }

    func indexURL() -> URL {
        baseURL.appendingPathComponent("sessions.json")
    }

    func transcriptURL(for session: Session) -> URL {
        sessionFolderURL(for: session).appendingPathComponent("transcript.json")
    }

    func partialTranscriptURL(for session: Session) -> URL {
        sessionFolderURL(for: session).appendingPathComponent("transcript.partial.json")
    }

    /// Save partial transcript during recording (for crash recovery).
    func savePartialTranscript(_ transcript: Transcript, for session: Session) {
        let url = partialTranscriptURL(for: session)
        Self.writeInBackground(transcript, to: url)
    }

    func audioPath(for sessionID: String) -> String? {
        guard let entry = sessions.first(where: { $0.id == sessionID }) else { return nil }
        let folder = baseURL.appendingPathComponent(entry.path)
        let m4a = folder.appendingPathComponent("audio.m4a")
        if fileManager.fileExists(atPath: m4a.path) { return m4a.path }
        let wav = folder.appendingPathComponent("audio.wav")
        if fileManager.fileExists(atPath: wav.path) { return wav.path }
        return m4a.path
    }

    // MARK: - Transcript

    func saveTranscript(_ transcript: Transcript, for session: Session) {
        // Update in-memory index on main thread (instant)
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            let isFirstTranscribe = sessions[idx].segmentCount == nil || sessions[idx].segmentCount == 0

            sessions[idx].hasTranscript = true
            sessions[idx].segmentCount = transcript.segments.count
            sessions[idx].model = transcript.model

            if isFirstTranscribe,
               let firstText = transcript.segments.first?.text, !firstText.isEmpty {
                let autoName = String(firstText.prefix(40)).trimmingCharacters(in: .whitespaces)
                if !autoName.isEmpty {
                    sessions[idx].name = autoName
                }
            }
        }

        // Write transcript and index to disk in background
        let url = transcriptURL(for: session)
        Self.writeInBackground(transcript, to: url)
        writeIndex()
    }

    func loadTranscript(for sessionID: String) -> Transcript? {
        guard let entry = sessions.first(where: { $0.id == sessionID }) else { return nil }
        let url = baseURL
            .appendingPathComponent(entry.path)
            .appendingPathComponent("transcript.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(Transcript.self, from: data)
        } catch {
            logger.error("Failed to load transcript: \(error)")
            return nil
        }
    }

    // MARK: - Summary

    func summaryURL(for sessionID: String) -> URL? {
        guard let entry = sessions.first(where: { $0.id == sessionID }) else { return nil }
        return baseURL
            .appendingPathComponent(entry.path)
            .appendingPathComponent("summary.json")
    }

    func saveSummary(_ summary: Summary, for sessionID: String) {
        guard let url = summaryURL(for: sessionID) else { return }
        Self.writeInBackground(summary, to: url)
        logger.info("Summary saved for session: \(sessionID)")
    }

    func loadSummary(for sessionID: String) -> Summary? {
        guard let url = summaryURL(for: sessionID),
              fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(Summary.self, from: data)
        } catch {
            logger.error("Failed to load summary: \(error)")
            return nil
        }
    }

    // MARK: - Persistence

    private func writeMetadata(_ session: Session) {
        let url = metadataURL(for: session)
        Self.writeInBackground(session, to: url)
    }

    private func updateIndex(session: Session) {
        let entry = SessionIndex.SessionEntry(
            id: session.id,
            name: session.name,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            model: nil,
            path: session.folderName,
            hasAudio: true,
            hasTranscript: false,
            segmentCount: nil,
            languagesDetected: nil
        )

        // Remove existing entry for this ID, add new one at front
        sessions.removeAll { $0.id == session.id }
        sessions.insert(entry, at: 0)
        writeIndex()
    }

    private func writeIndex() {
        let index = SessionIndex(sessions: sessions)
        let url = indexURL()
        Self.writeInBackground(index, to: url)
    }

    private func loadIndex() {
        let url = indexURL()
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let index = try decoder.decode(SessionIndex.self, from: data)
            sessions = index.sessions
        } catch {
            logger.error("Failed to load sessions index: \(error)")
        }
    }

    // MARK: - Session Management

    func pinSession(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = true
        writeIndex()
    }

    func unpinSession(id: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned = nil
        writeIndex()
    }

    func renameSession(id: String, newName: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].name = newName
        writeIndex()

        // Update metadata.json on disk in background
        let metaURL = baseURL
            .appendingPathComponent(sessions[idx].path)
            .appendingPathComponent("metadata.json")
        Self.ioQueue.async {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = try? Data(contentsOf: metaURL),
               var session = try? decoder.decode(Session.self, from: data) {
                session.name = newName
                Self.writeInBackground(session, to: metaURL)
            }
        }
    }

    func deleteSession(id: String) {
        guard let entry = sessions.first(where: { $0.id == id }) else { return }
        let folderURL = baseURL.appendingPathComponent(entry.path)
        do {
            try fileManager.trashItem(at: folderURL, resultingItemURL: nil)
        } catch {
            // Fallback to direct removal if trash fails
            do {
                try fileManager.removeItem(at: folderURL)
            } catch {
                logger.error("Failed to delete session folder: \(error)")
            }
        }
        sessions.removeAll { $0.id == id }
        writeIndex()
    }

    func importAudioFile(from sourceURL: URL) -> Session? {
        let now = Date()
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let id = Session.makeID(date: now)
        let session = Session(
            id: id, name: name, startedAt: now, endedAt: now,
            durationSeconds: audioDuration(url: sourceURL),
            status: .complete
        )

        let folderURL = baseURL.appendingPathComponent(session.folderName)
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let destURL = folderURL.appendingPathComponent("audio.m4a")
            try fileManager.copyItem(at: sourceURL, to: destURL)
            writeMetadata(session)
            updateIndex(session: session)
            return session
        } catch {
            logger.error("Failed to import audio: \(error)")
            return nil
        }
    }

    private func audioDuration(url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        guard duration.timescale > 0 else { return nil }
        return Double(duration.value) / Double(duration.timescale)
    }
}
