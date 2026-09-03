import AVFoundation
import Foundation

enum VideoConverterError: LocalizedError {
    case unreadableVideo
    case unsupportedVideo
    case noVideoTrack
    case exportFailed(String)
    case insufficientStorage
    case photoLibraryAccessDenied

    var errorDescription: String? {
        switch self {
        case .unreadableVideo:
            return "動画を正常に読み込めませんでした。ファイルが壊れている可能性があります。"
        case .unsupportedVideo, .noVideoTrack:
            return "この動画は読み込めませんでした。"
        case .exportFailed:
            return "動画を変換できませんでした。"
        case .insufficientStorage:
            return "保存先の空き容量が足りません。"
        case .photoLibraryAccessDenied:
            return "写真アプリへのアクセスが許可されていません。"
        }
    }
}

enum VideoOrientation: Equatable, Sendable {
    case landscape
    case portrait
    case square
}

struct VideoSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

struct VideoAnalysis: Sendable {
    let sourceURL: URL
    let duration: Double
    let displaySize: VideoSize
    let orientation: VideoOrientation
    let frameRate: Double
    let codec: String
    let hasAudio: Bool
    let creationDate: Date
}

struct ConversionSegment: Equatable, Sendable {
    let index: Int
    let start: Double
    let duration: Double
    let creationDate: Date
}

struct ConversionPlan: Equatable, Sendable {
    static let maximumSegmentDuration = 119.0

    let outputSize: VideoSize
    let outputFrameRate: Double
    let segments: [ConversionSegment]
}

struct VideoAnalyzer {
    func analyze(url: URL) async throws -> VideoAnalysis {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw VideoConverterError.noVideoTrack
        }

        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else {
            throw VideoConverterError.unreadableVideo
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        let displayWidth = max(1, Int(round(abs(transformedRect.width))))
        let displayHeight = max(1, Int(round(abs(transformedRect.height))))
        let orientation: VideoOrientation
        if displayWidth == displayHeight {
            orientation = .square
        } else if displayWidth > displayHeight {
            orientation = .landscape
        } else {
            orientation = .portrait
        }

        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let creationDate = await Self.creationDate(asset: asset, url: url)
        let codec = try await Self.codecName(track: videoTrack)

        return VideoAnalysis(
            sourceURL: url,
            duration: duration,
            displaySize: VideoSize(width: displayWidth, height: displayHeight),
            orientation: orientation,
            frameRate: Double(nominalFrameRate),
            codec: codec,
            hasAudio: tracks.contains { $0.mediaType == .audio },
            creationDate: creationDate
        )
    }

    private static func creationDate(asset: AVAsset, url: URL) async -> Date {
        if let metadataDate = try? await asset.load(.creationDate) {
            if let date = try? await metadataDate.load(.dateValue) {
                return date
            }
        }

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date()
    }

    private static func codecName(track: AVAssetTrack) async throws -> String {
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first else {
            return "unknown"
        }
        switch CMFormatDescriptionGetMediaSubType(description) {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        default: return "unknown"
        }
    }
}

struct ConversionPlanner {
    func plan(for analysis: VideoAnalysis) -> ConversionPlan {
        let segmentCount = max(1, Int(ceil(analysis.duration / ConversionPlan.maximumSegmentDuration)))
        let segmentDuration = analysis.duration / Double(segmentCount)
        let segments = (0..<segmentCount).map { index in
            ConversionSegment(
                index: index,
                start: Double(index) * segmentDuration,
                duration: segmentDuration,
                creationDate: analysis.creationDate.addingTimeInterval(Double(index) * segmentDuration)
            )
        }

        return ConversionPlan(
            outputSize: outputSize(for: analysis.displaySize),
            outputFrameRate: min(30, max(1, analysis.frameRate > 0 ? analysis.frameRate : 30)),
            segments: segments
        )
    }

    private func outputSize(for source: VideoSize) -> VideoSize {
        let maxWidth: Double = 1280
        let maxHeight: Double = 720
        let isPortrait = source.height > source.width
        let bounds = isPortrait ? (width: maxHeight, height: maxWidth) : (width: maxWidth, height: maxHeight)
        let scale = min(1, bounds.width / Double(source.width), bounds.height / Double(source.height))
        let width = even(max(2, Int(floor(Double(source.width) * scale))))
        let height = even(max(2, Int(floor(Double(source.height) * scale))))
        return VideoSize(width: width, height: height)
    }

    private func even(_ value: Int) -> Int {
        value.isMultiple(of: 2) ? value : value - 1
    }
}
