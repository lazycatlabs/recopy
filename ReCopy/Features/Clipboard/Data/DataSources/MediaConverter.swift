import AVFoundation
import Foundation

/// Re-encodes video and audio files for Paste Special, and estimates the size of each result before it's made.
/// Everything runs off the main thread.
nonisolated enum MediaConverter {
    enum Failure: Error {
        case unreadable, noAudio, unsupported
    }

    /// Seconds between progress updates while a video exports.
    private static let progressInterval: TimeInterval = 0.2

    // MARK: Reading

    @concurrent static func info(of url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let seconds = try await asset.load(.duration).seconds
        var info = MediaInfo(seconds: seconds.isFinite ? seconds : 0, hasAudio: false, sampleRate: 0, channels: 0)
        if let video = try await asset.loadTracks(withMediaType: .video).first {
            let (size, transform) = try await video.load(.naturalSize, .preferredTransform)
            let shown = size.applying(transform)
            info.width = Int(abs(shown.width).rounded())
            info.height = Int(abs(shown.height).rounded())
        }
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            info.hasAudio = true
            let format = try await audio.load(.formatDescriptions).first
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            info.sampleRate = format?.mSampleRate ?? 0
            info.channels = Int(format?.mChannelsPerFrame ?? 0)
        }
        guard info.width != nil || info.hasAudio else { throw Failure.unreadable }
        return info
    }

    // MARK: Video

    /// The size AVFoundation expects the export to have, or nil when it can't tell (it then answers 0).
    @concurrent static func estimatedBytes(of url: URL, preset: VideoPreset, removingAudio: Bool) async -> Int64? {
        guard let asset = try? await videoAsset(url, removingAudio: removingAudio),
              let session = AVAssetExportSession(asset: asset, presetName: preset.exportPreset),
              let bytes = try? await session.estimatedOutputFileLengthInBytes, bytes > 0 else { return nil }
        return bytes
    }

    /// Writes the video to `output`, calling `progress` with 0…1 as it goes. Cancelling the task stops the export.
    @concurrent static func exportVideo(_ url: URL, options: VideoPasteOptions, to output: URL,
                                        progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = try await videoAsset(url, removingAudio: options.removesAudio)
        guard let session = AVAssetExportSession(asset: asset, presetName: options.preset.exportPreset),
              await AVAssetExportSession.compatibility(ofExportPreset: options.preset.exportPreset, with: asset,
                                                       outputFileType: options.container.fileType)
        else { throw Failure.unsupported }
        let states = session.states(updateInterval: progressInterval)
        let monitor = Task {
            for await state in states {
                if case .exporting(let exporting) = state { progress(exporting.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: output, as: options.container.fileType)
    }

    /// The file itself, or, without its sound, a composition of only its video tracks.
    private static func videoAsset(_ url: URL, removingAudio: Bool) async throws -> AVAsset {
        let asset = AVURLAsset(url: url)
        guard removingAudio else { return asset }
        let composition = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) {
            let (range, transform) = try await track.load(.timeRange, .preferredTransform)
            guard let copy = composition.addMutableTrack(withMediaType: .video,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try copy.insertTimeRange(range, of: track, at: range.start)
            copy.preferredTransform = transform
        }
        return composition
    }

    // MARK: Audio

    /// Writes the sound of `url` (an audio file, or a video's soundtrack) to `output` as AAC or WAV, mixed down to
    /// stereo at most, calling `progress` with 0…1. Cancelling the task stops it and leaves no file.
    @concurrent static func exportAudio(_ url: URL, preset: AudioPreset, info: MediaInfo, to output: URL,
                                        progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw Failure.noAudio }
        let channels = AudioPreset.channels(info.channels)
        let sampleRate = preset.sampleRate(for: info.sampleRate)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: pcmSettings(sampleRate, channels))
        guard reader.canAdd(readerOutput) else { throw Failure.unsupported }
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: preset.fileType)
        var settings = pcmSettings(sampleRate, channels)
        if let bitRate = preset.bitsPerSecond {
            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
                        AVEncoderBitRateKey: bitRate,
                        // Constant, so the size shown before converting is the size it ends up.
                        AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant]
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw Failure.unsupported }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else { throw reader.error ?? writer.error ?? Failure.unreadable }
        writer.startSession(atSourceTime: .zero)
        do {
            try await copySamples(from: readerOutput, to: input, seconds: info.seconds, progress: progress)
            if reader.status == .failed { throw reader.error ?? Failure.unreadable }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? Failure.unsupported }
    }

    private static func copySamples(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, seconds: Double,
                                    progress: @Sendable (Double) -> Void) async throws {
        while let buffer = output.copyNextSampleBuffer() {
            // ponytail: polls the writer every few ms; requestMediaDataWhenReady if this ever shows up in a profile.
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
            try Task.checkCancellation()
            guard input.append(buffer) else { throw Failure.unsupported }
            if seconds > 0 { progress(min(1, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / seconds)) }
        }
    }

    /// 16-bit interleaved samples: what the reader decodes to, and what WAV stores.
    private static func pcmSettings(_ sampleRate: Double, _ channels: Int) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
         AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
         AVLinearPCMIsNonInterleaved: false]
    }
}
