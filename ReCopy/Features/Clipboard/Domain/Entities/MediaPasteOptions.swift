import AVFoundation
import UniformTypeIdentifiers

/// A copied file Paste Special can re-encode: a video, or an audio file.
nonisolated enum MediaKind: Sendable {
    case video, audio

    init?(fileExtension: String) {
        guard let type = UTType(filenameExtension: fileExtension) else { return nil }
        if type.conforms(to: .movie) {
            self = .video
        } else if type.conforms(to: .audio) {
            self = .audio
        } else {
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        }
    }
}

/// The video file types Paste Special writes. M4V is MP4 as Apple apps name it.
nonisolated enum VideoContainer: String, CaseIterable, Identifiable, Sendable {
    case mp4, mov, m4v

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var fileType: AVFileType {
        switch self {
        case .mp4: .mp4
        case .mov: .mov
        case .m4v: .m4v
        }
    }
}

/// A video size and codec, as one of AVFoundation's export presets (they only exist in these pairs).
nonisolated enum VideoPreset: String, CaseIterable, Identifiable, Sendable {
    case hevcOriginal, avcOriginal, hevc4K, avc4K, hevc1080, avc1080, avc720, avc540, avc480

    var id: String { rawValue }

    var exportPreset: String {
        switch self {
        case .hevcOriginal: AVAssetExportPresetHEVCHighestQuality
        case .avcOriginal: AVAssetExportPresetHighestQuality
        case .hevc4K: AVAssetExportPresetHEVC3840x2160
        case .avc4K: AVAssetExportPreset3840x2160
        case .hevc1080: AVAssetExportPresetHEVC1920x1080
        case .avc1080: AVAssetExportPreset1920x1080
        case .avc720: AVAssetExportPreset1280x720
        case .avc540: AVAssetExportPreset960x540
        case .avc480: AVAssetExportPreset640x480
        }
    }

    /// The longest side the preset scales down to; nil keeps the video's size.
    var longestSide: Int? {
        switch self {
        case .hevcOriginal, .avcOriginal: nil
        case .hevc4K, .avc4K: 3840
        case .hevc1080, .avc1080: 1920
        case .avc720: 1280
        case .avc540: 960
        case .avc480: 640
        }
    }

    var isHEVC: Bool { [.hevcOriginal, .hevc4K, .hevc1080].contains(self) }

    /// "1080p", or nil for the video's own size.
    var resolution: String? {
        switch self {
        case .hevcOriginal, .avcOriginal: nil
        case .hevc4K, .avc4K: "4K"
        case .hevc1080, .avc1080: "1080p"
        case .avc720: "720p"
        case .avc540: "540p"
        case .avc480: "480p"
        }
    }

    var codec: String { isHEVC ? "HEVC" : "H.264" }

    /// The presets worth offering for a video whose longest side is `longestSide`: none that would scale it up.
    static func offered(forLongestSide longestSide: Int) -> [VideoPreset] {
        allCases.filter { ($0.longestSide ?? 0) <= longestSide }
    }
}

/// An audio format and bitrate. AAC files are M4A; WAV keeps every sample (16-bit).
nonisolated enum AudioPreset: String, CaseIterable, Identifiable, Sendable {
    case aac64, aac128, aac192, aac256, wav

    var id: String { rawValue }

    var bitsPerSecond: Int? {
        switch self {
        case .aac64: 64_000
        case .aac128: 128_000
        case .aac192: 192_000
        case .aac256: 256_000
        case .wav: nil
        }
    }

    var fileType: AVFileType { self == .wav ? .wav : .m4a }
    /// Named outright: the system's preferred extension for AAC audio is .mp4.
    var fileExtension: String { self == .wav ? "wav" : "m4a" }
    var format: String { self == .wav ? "WAV" : "AAC" }

    /// The file's size for `seconds` of sound. AAC is the bitrate times the length; WAV is every 16-bit sample.
    func estimatedBytes(seconds: Double, sampleRate: Double, channels: Int) -> Int64 {
        let bytesPerSecond = bitsPerSecond.map { Double($0) / 8 }
            ?? AudioPreset.wavSampleRate(sampleRate) * Double(AudioPreset.channels(channels) * 2)
        return Int64((bytesPerSecond * seconds).rounded())
    }

    /// AAC goes up to 48 kHz; WAV keeps the source's rate.
    func sampleRate(for source: Double) -> Double {
        self == .wav ? Self.wavSampleRate(source) : min(source > 0 ? source : 44_100, 48_000)
    }

    private static func wavSampleRate(_ source: Double) -> Double { source > 0 ? source : 44_100 }

    /// Mono or stereo: more channels are mixed down to two.
    static func channels(_ source: Int) -> Int { min(max(source, 1), 2) }
}

/// How Paste Special re-encodes a video.
nonisolated struct VideoPasteOptions: Hashable, Sendable {
    var preset = VideoPreset.hevc1080
    var container = VideoContainer.mp4
    var removesAudio = false
}

/// What Paste Special needs to know about a video or audio file before converting it.
nonisolated struct MediaInfo: Sendable, Equatable {
    var seconds: Double
    /// The video's displayed size (rotation applied); nil for audio.
    var width: Int?
    var height: Int?
    var hasAudio: Bool
    var sampleRate: Double
    var channels: Int
}
