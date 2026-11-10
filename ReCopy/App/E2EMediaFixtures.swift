#if DEBUG
import AVFoundation
import CoreGraphics
import CoreVideo

/// Sample files for the E2E tests' video and audio Paste Special: three seconds of a 440 Hz tone (Sample.wav), and
/// the same tone under 1280 × 720 frames that fade from orange to indigo (Sample.mov).
nonisolated enum E2EMediaFixtures {
    enum Failure: Error { case setup }

    private static let seconds = 3
    private static let framesPerSecond: Int32 = 10
    private static let size = (width: 1280, height: 720)

    @concurrent static func make(video: Bool, in folder: URL) async throws -> URL {
        let wav = folder.appending(path: "Sample.wav")
        try writeTone(to: wav)
        guard video else { return wav }
        let frames = folder.appending(path: "Frames.mov")
        try await writeFrames(to: frames)
        let movie = folder.appending(path: "Sample.mov")
        try await combine(frames, wav, into: movie)
        try? FileManager.default.removeItem(at: frames)
        return movie
    }

    private static func writeTone(to url: URL) throws {
        let rate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate) * AVAudioFrameCount(seconds))
        else { throw Failure.setup }
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            guard let samples = buffer.floatChannelData?[channel] else { throw Failure.setup }
            for frame in 0..<Int(buffer.frameLength) { samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / rate)) * 0.3 }
        }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }

    private static func writeFrames(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.setup }
        writer.startSession(atSourceTime: .zero)
        let count = seconds * Int(framesPerSecond)
        for index in 0..<count {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? Failure.setup }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else { throw Failure.setup }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let pixels = made else { throw Failure.setup }
            draw(into: pixels, progress: CGFloat(index) / CGFloat(count - 1))
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: framesPerSecond))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? Failure.setup }
    }

    private static func draw(into pixels: CVPixelBuffer, progress: CGFloat) {
        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        context.setFillColor(red: 1 - progress * 0.7, green: 0.55 - progress * 0.3, blue: 0.2 + progress * 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.setFillColor(.white)
        let side = CGFloat(size.height) / 3
        context.fillEllipse(in: CGRect(x: progress * (CGFloat(size.width) - side), y: side, width: side, height: side))
    }

    /// The frames with the tone as their soundtrack, copied as they are.
    private static func combine(_ frames: URL, _ sound: URL, into url: URL) async throws {
        let composition = AVMutableComposition()
        for (source, type) in [(frames, AVMediaType.video), (sound, .audio)] {
            // Kept in a constant: a track whose asset is already released can't be inserted.
            let asset = AVURLAsset(url: source)
            guard let track = try await asset.loadTracks(withMediaType: type).first,
                  let copy = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw Failure.setup }
            try copy.insertTimeRange(try await track.load(.timeRange), of: track, at: .zero)
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { throw Failure.setup }
        try await session.export(to: url, as: .mov)
    }
}
#endif
