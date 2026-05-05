import AVFoundation
import SwiftUI

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var progress: Double = 0

    private var player: AVAudioPlayer?
    private var updateTimer: Timer?
    private var loadedURL: URL?

    func load(url: URL) {
        guard url != loadedURL else { return }
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            loadedURL = url
            duration = p.duration
            currentTime = 0
            progress = 0
        } catch {
            print("AudioPlayerService: failed to load \(url.lastPathComponent): \(error)")
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        let clamped = min(max(fraction, 0), 1)
        player.currentTime = clamped * player.duration
        updatePublishedState()
    }

    func seek(toTime seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(seconds, 0), player.duration)
        updatePublishedState()
    }

    func stop() {
        player?.stop()
        stopTimer()
        player = nil
        loadedURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        progress = 0
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePublishedState()
            }
        }
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updatePublishedState() {
        guard let player else { return }
        currentTime = player.currentTime
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.stopTimer()
            self.currentTime = 0
            self.progress = 0
            self.player?.currentTime = 0
        }
    }
}
