import Foundation
import Observation
import os

/// Paste Special for a video or audio file: what the file holds, the chosen options, each option's estimated size,
/// and the export's progress.
@Observable
final class MediaPasteSpecialModel {
    /// The last options used, so the next Paste Special starts from them (kept until ReCopy quits).
    private static var lastVideo = VideoPasteOptions()
    private static var lastAudio = AudioPreset.aac128

    let item: ClipItem
    let url: URL
    let kind: MediaKind
    let originalBytes: Int64?
    var video: VideoPasteOptions {
        didSet { Self.lastVideo = video }
    }
    var audio: AudioPreset {
        didSet { Self.lastAudio = audio }
    }
    /// Nil until the file's been read.
    private(set) var info: MediaInfo?
    /// Estimated sizes by preset id: no entry while it's being estimated, nil if AVFoundation couldn't tell.
    private(set) var estimates: [String: Int64?] = [:]
    /// 0…1 while exporting, nil otherwise.
    private(set) var progress: Double?
    private(set) var hasFailed = false
    private var export: Task<Void, Never>?

    init(item: ClipItem, url: URL, kind: MediaKind) {
        self.item = item
        self.url = url
        self.kind = kind
        video = Self.lastVideo
        audio = Self.lastAudio
        originalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    /// The video presets that fit this video (none that scale it up), once it's been read.
    var videoPresets: [VideoPreset] {
        guard let info, let width = info.width, let height = info.height else { return [] }
        return VideoPreset.offered(forLongestSide: max(width, height))
    }

    var isExporting: Bool { progress != nil }

    /// Reads the file's length, size and sound, before the sheet is shown so it opens at its full size.
    /// - Returns: false if it isn't a video or audio file AVFoundation can read.
    func read() async -> Bool {
        do {
            info = try await MediaConverter.info(of: url)
        } catch {
            Log.storage.error("Paste Special couldn't read media: \(error.localizedDescription, privacy: .public)")
            return false
        }
        if kind == .video, !videoPresets.contains(video.preset), let first = videoPresets.first { video.preset = first }
        return !(kind == .video && videoPresets.isEmpty)
    }

    /// Estimates every option's size. Video estimates are redone when the sound is removed or kept, as it changes them.
    func estimate() async {
        guard let info else { return }
        estimates = [:]
        switch kind {
        case .audio:
            for preset in AudioPreset.allCases {
                estimates[preset.id] = preset.estimatedBytes(seconds: info.seconds, sampleRate: info.sampleRate,
                                                             channels: info.channels)
            }
        case .video:
            let url = url, removesAudio = video.removesAudio
            // One at a time: each estimate opens the file, and they're quick.
            for preset in videoPresets {
                let bytes = await MediaConverter.estimatedBytes(of: url, preset: preset, removingAudio: removesAudio)
                guard !Task.isCancelled else { return }
                estimates[preset.id] = .some(bytes)
            }
        }
    }

    /// Exports with the chosen options into a folder of its own, then hands the file to `done`. The files already on
    /// the clipboard stay until then, so a failed or cancelled export leaves them alone. Does nothing while an export
    /// runs; a failure is shown in the sheet.
    func start(done: @escaping (URL) -> Void) {
        guard !isExporting, let info else { return }
        hasFailed = false
        progress = 0
        let source = url, kind = kind, video = video, audio = audio
        let name = (url.lastPathComponent as NSString).deletingPathExtension
        let staging = FileManager.default.temporaryDirectory.appending(path: "PasteSpecialExport-\(UUID().uuidString)")
        export = Task {
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let ext = kind == .video ? video.container.rawValue : audio.fileExtension
                let output = staging.appending(path: name).appendingPathExtension(ext)
                let report: @Sendable (Double) -> Void = { value in
                    Task { @MainActor in self.report(value) }
                }
                switch kind {
                case .video: try await MediaConverter.exportVideo(source, options: video, to: output, progress: report)
                case .audio: try await MediaConverter.exportAudio(source, preset: audio, info: info, to: output, progress: report)
                }
                try Task.checkCancellation()
                progress = nil
                done(output)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: staging)
                progress = nil
            } catch {
                try? FileManager.default.removeItem(at: staging)
                Log.storage.error("Paste Special export failed: \(error.localizedDescription, privacy: .public)")
                progress = nil
                hasFailed = !Task.isCancelled
            }
        }
    }

    /// Stops a running export (the window closed).
    func cancel() {
        export?.cancel()
        export = nil
    }

    private func report(_ value: Double) {
        if isExporting { progress = value }
    }
}
