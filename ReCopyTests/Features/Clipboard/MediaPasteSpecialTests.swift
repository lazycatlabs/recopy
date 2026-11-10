import AppKit
import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import ReCopy

struct MediaPasteSpecialTests {
    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(ext)")
    }

    /// `seconds` of a 440 Hz tone, stereo 44.1 kHz.
    private func makeWAV(seconds: Double) throws -> URL {
        let url = temporaryURL("wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) { samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100)) * 0.5 }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    /// One second of grey 1280×720 H.264 video, without sound.
    private func makeVideo() async throws -> URL {
        let url = temporaryURL("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let pool = try #require(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 128, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    @Test func findsVideoAndAudioFiles() {
        #expect(MediaKind(fileExtension: "mp4") == .video)
        #expect(MediaKind(fileExtension: "MOV") == .video)
        #expect(MediaKind(fileExtension: "m4a") == .audio)
        #expect(MediaKind(fileExtension: "mp3") == .audio)
        #expect(MediaKind(fileExtension: "png") == nil)

        let video = ClipItem(kind: .file, files: [ClipFile(path: "/tmp/Clip.mp4", name: "Clip.mp4")], hash: "v",
                             firstCopied: .now, lastCopied: .now)
        #expect(video.convertibleMedia?.kind == .video)
        #expect(ClipAction.available(for: video).contains(.pasteSpecial))
        var two = video
        two.files?.append(ClipFile(path: "/tmp/Song.mp3", name: "Song.mp3"))
        #expect(two.convertibleMedia == nil, "Only one file at a time")
        #expect(!ClipAction.available(for: two).contains(.pasteSpecial))
    }

    @Test func offersNoPresetThatScalesUp() {
        #expect(VideoPreset.offered(forLongestSide: 1280) == [.hevcOriginal, .avcOriginal, .avc720, .avc540, .avc480])
        #expect(VideoPreset.offered(forLongestSide: 3840) == VideoPreset.allCases)
    }

    @Test func estimatesAudioSizes() {
        #expect(AudioPreset.aac128.estimatedBytes(seconds: 60, sampleRate: 44_100, channels: 2) == 960_000)
        // WAV: every 16-bit sample, five channels mixed down to stereo.
        #expect(AudioPreset.wav.estimatedBytes(seconds: 1, sampleRate: 48_000, channels: 5) == 192_000)
        #expect(AudioPreset.aac64.sampleRate(for: 96_000) == 48_000)
        #expect(AudioPreset.wav.sampleRate(for: 96_000) == 96_000)
    }

    @Test(arguments: [AudioPreset.aac64, .wav])
    func convertsAudioCloseToItsEstimate(preset: AudioPreset) async throws {
        let source = try makeWAV(seconds: 3)
        let output = temporaryURL(preset == .wav ? "wav" : "m4a")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        let info = try await MediaConverter.info(of: source)
        #expect(info.hasAudio && info.channels == 2 && info.width == nil)

        try await MediaConverter.exportAudio(source, preset: preset, info: info, to: output) { _ in }
        let converted = try await MediaConverter.info(of: output)
        #expect(abs(converted.seconds - 3) < 0.1)
        let bytes = try #require(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let estimate = preset.estimatedBytes(seconds: info.seconds, sampleRate: info.sampleRate, channels: info.channels)
        #expect(abs(Double(bytes) - Double(estimate)) / Double(estimate) < 0.1, "\(bytes) bytes, estimated \(estimate)")
    }

    @Test func videoWithoutSoundHasNoAudio() async throws {
        let source = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: source) }
        let output = temporaryURL("m4a")
        await #expect(throws: MediaConverter.Failure.self) {
            try await MediaConverter.exportAudio(source, preset: .aac128,
                                                 info: MediaInfo(seconds: 1, hasAudio: false, sampleRate: 0, channels: 0),
                                                 to: output) { _ in }
        }
    }

    @MainActor @Test func exportReplacesThePreviousOneOnlyOnceItsOnTheClipboard() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let board = NSPasteboard(name: .init(UUID().uuidString))
        let session = ClipboardSession(root: root, pasteboard: SystemPasteboard(pasteboard: board))
        let item = ClipItem(kind: .file, files: [ClipFile(path: "/tmp/Clip.mov", name: "Clip.mov")], hash: "m",
                            firstCopied: .now, lastCopied: .now)
        func export(_ name: String) throws -> URL {
            let folder = FileManager.default.temporaryDirectory.appending(path: "PasteSpecialExport-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: name)
            try Data("video".utf8).write(to: file)
            return file
        }
        let first = try export("Clip.mov"), second = try export("Clip.mp4")

        #expect(session.writeExported(first, for: item, pasting: false))
        #expect(FileManager.default.fileExists(atPath: first.path), "Stays while it's on the clipboard")
        #expect(session.writeExported(second, for: item, pasting: false))
        let copied = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(copied == [second])
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path), "The replaced export is removed")
        try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
    }

    @Test func shrinksVideoToTheChosenSizeAndType() async throws {
        let source = try await makeVideo()
        let output = temporaryURL("mp4")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }
        let info = try await MediaConverter.info(of: source)
        #expect(info.width == 1280 && info.height == 720 && !info.hasAudio)

        let options = VideoPasteOptions(preset: .avc480, container: .mp4, removesAudio: true)
        try await MediaConverter.exportVideo(source, options: options, to: output) { _ in }
        let converted = try await MediaConverter.info(of: output)
        #expect(converted.width == 640 && converted.height == 360)
        #expect(try output.resourceValues(forKeys: [.contentTypeKey]).contentType == .mpeg4Movie)
    }
}
