import SwiftUI

/// Shown in its own window at the pointer. Re-encodes a video (size, codec, file type, without its sound) or an audio
/// file (AAC bitrate or WAV), showing each option's estimated size first, then pastes or copies the new file.
struct MediaPasteSpecialPage: View {
    @Bindable var model: MediaPasteSpecialModel
    let finish: (_ pasting: Bool) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(L(.pasteSpecialTitle), systemImage: ClipAction.pasteSpecial.symbolName)
                    .font(.scaled(.title3, weight: .semibold))
                Text(original)
                    .font(.scaled(.callout))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pasteSpecial.original")
            }
            if model.kind == .video {
                PasteSpecialRow(title: L(.pasteSpecialFormat)) {
                    Picker(L(.pasteSpecialFormat), selection: $model.video.container) {
                        ForEach(VideoContainer.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("pasteSpecial.container")
                }
            }
            PasteSpecialRow(title: L(.pasteSpecialQuality)) {
                VStack(spacing: Spacing.xxs) {
                    switch model.kind {
                    case .video:
                        ForEach(model.videoPresets) { preset in
                            option(preset.id, title: preset.resolution ?? L(.pasteSpecialOriginalResolution),
                                   detail: preset.codec, selected: model.video.preset == preset) { model.video.preset = preset }
                        }
                    case .audio:
                        ForEach(AudioPreset.allCases) { preset in
                            option(preset.id, title: preset.format, detail: preset.detail,
                                   selected: model.audio == preset) { model.audio = preset }
                        }
                    }
                }
            }
            if model.kind == .video {
                Toggle(L(.pasteSpecialRemoveAudio), isOn: $model.video.removesAudio)
                    .disabled(model.info?.hasAudio != true)
                    .accessibilityIdentifier("pasteSpecial.removeAudio")
            }
            status
            PasteSpecialButtons(finish: finish, cancel: cancel)
                .disabled(model.isExporting)
        }
        .pasteSpecialCard()
        .task(id: model.video.removesAudio) { await model.estimate() }
    }

    private func option(_ id: String, title: String, detail: String, selected: Bool,
                        select: @escaping () -> Void) -> some View {
        OptionItem(title: title, detail: detail, estimate: model.estimates[id], original: model.originalBytes,
                   isSelected: selected, select: select)
            .disabled(model.isExporting)
            .accessibilityIdentifier("pasteSpecial.option.\(id)")
    }

    /// The file as it is: size on disk, picture size and length.
    private var original: String {
        var parts = [model.originalBytes?.formatted(.byteCount(style: .file)) ?? "—"]
        if let width = model.info?.width, let height = model.info?.height { parts.append("\(width)×\(height)") }
        if let seconds = model.info?.seconds {
            parts.append(Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond)))
        }
        return L(.pasteSpecialOriginal(parts.joined(separator: " · ")))
    }

    /// The export's progress, a failure, or a reminder that the sizes are estimates. One line either way.
    @ViewBuilder private var status: some View {
        if let progress = model.progress {
            HStack(spacing: Spacing.md) {
                ProgressView(value: progress)
                Text(progress.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
            }
            .font(.scaled(.callout))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("pasteSpecial.progress")
        } else {
            Text(model.hasFailed ? L(.pasteSpecialMediaFailed) : L(.pasteSpecialEstimateNote))
                .font(.scaled(.callout))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pasteSpecial.summary")
        }
    }
}

/// One choice of size and codec (or format and bitrate), with what the file would weigh and how that compares.
private struct OptionItem: View {
    let title: String
    let detail: String
    /// No value while estimating; nil inside when it couldn't be estimated.
    let estimate: Int64??
    let original: Int64?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title).fontWeight(.medium)
                Text(detail).foregroundStyle(.secondary)
                Spacer()
                Text(size).monospacedDigit()
                if let change {
                    Text(change.formatted(.percent.sign(strategy: .always()).precision(.fractionLength(0))))
                        .monospacedDigit()
                        // Not smaller than the file already is: worth a second look.
                        .foregroundStyle(change >= 0 ? .orange : .secondary)
                }
            }
            .font(.scaled(.callout))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? Color.accentColor.opacity(Opacity.fill) : .clear, in: .rect(cornerRadius: Radius.sm))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var size: String {
        guard let estimate else { return "…" }
        return estimate.map { "≈ " + $0.formatted(.byteCount(style: .file)) } ?? "—"
    }

    /// The estimate against the original size, e.g. −0.84.
    private var change: Double? {
        guard let estimate = estimate ?? nil, let original, original > 0 else { return nil }
        return Double(estimate - original) / Double(original)
    }
}

private extension AudioPreset {
    var detail: String {
        bitsPerSecond.map { "\($0 / 1_000) kbps" } ?? L(.pasteSpecialLossless)
    }
}
