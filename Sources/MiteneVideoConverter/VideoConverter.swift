@preconcurrency import AVFoundation
import Foundation

private extension AVAssetExportSession.Status {
    var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

@MainActor
final class VideoConverter {
    func convert(
        analysis: VideoAnalysis,
        plan: ConversionPlan,
        outputDirectory: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let asset = AVURLAsset(url: analysis.sourceURL)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw VideoConverterError.noVideoTrack
        }
        let sourceSize = try await videoTrack.load(.naturalSize)
        let sourceTransform = try await videoTrack.load(.preferredTransform)

        var outputs: [URL] = []
        for (position, segment) in plan.segments.enumerated() {
            try Task.checkCancellation()
            let outputURL = uniqueOutputURL(
                sourceURL: analysis.sourceURL,
                segment: segment,
                segmentCount: plan.segments.count,
                directory: outputDirectory
            )
            let session = try makeExportSession(
                asset: asset,
                videoTrack: videoTrack,
                sourceSize: sourceSize,
                sourceTransform: sourceTransform,
                plan: plan,
                segment: segment
            )
            session.outputURL = outputURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            session.metadata = metadata(for: segment.creationDate)

            try await export(session) { segmentProgress in
                let overall = (Double(position) + Double(segmentProgress)) / Double(plan.segments.count)
                progress(overall)
            }
            try? FileManager.default.setAttributes(
                [.creationDate: segment.creationDate, .modificationDate: segment.creationDate],
                ofItemAtPath: outputURL.path
            )
            outputs.append(outputURL)
            progress(Double(position + 1) / Double(plan.segments.count))
        }
        return outputs
    }

    private func makeExportSession(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        sourceSize: CGSize,
        sourceTransform: CGAffineTransform,
        plan: ConversionPlan,
        segment: ConversionSegment
    ) throws -> AVAssetExportSession {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw VideoConverterError.unsupportedVideo
        }

        let segmentRange = CMTimeRange(
            start: CMTime(seconds: segment.start, preferredTimescale: 600),
            duration: CMTime(seconds: segment.duration, preferredTimescale: 600)
        )

        let composition = AVMutableVideoComposition()
        let transformedRect = CGRect(origin: .zero, size: sourceSize).applying(sourceTransform).standardized
        let displayedWidth = max(1, abs(transformedRect.width))
        let displayedHeight = max(1, abs(transformedRect.height))
        let scale = min(
            CGFloat(plan.outputSize.width) / displayedWidth,
            CGFloat(plan.outputSize.height) / displayedHeight
        )
        let scaledTransform = sourceTransform
            .translatedBy(x: -transformedRect.minX, y: -transformedRect.minY)
            .scaledBy(x: scale, y: scale)

        composition.renderSize = CGSize(width: plan.outputSize.width, height: plan.outputSize.height)
        composition.frameDuration = CMTime(value: 1, timescale: Int32(max(1, min(30, round(plan.outputFrameRate)))))
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = segmentRange
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(scaledTransform, at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        session.videoComposition = composition
        session.timeRange = segmentRange
        return session
    }

    private func export(_ session: AVAssetExportSession, progress: @escaping (Float) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let pollingTask = Task { @MainActor in
                while !session.status.isTerminal {
                    progress(session.progress)
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
            session.exportAsynchronously {
                pollingTask.cancel()
                if session.status == .completed {
                    continuation.resume()
                } else if let error = session.error {
                    continuation.resume(throwing: VideoConverterError.exportFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: VideoConverterError.exportFailed("Export ended unexpectedly"))
                }
            }
        }
    }

    private func metadata(for date: Date) -> [AVMetadataItem] {
        let value = ISO8601DateFormatter().string(from: date)
        let common = AVMutableMetadataItem()
        common.identifier = .commonIdentifierCreationDate
        common.value = value as NSString

        let quickTime = AVMutableMetadataItem()
        quickTime.identifier = .quickTimeMetadataCreationDate
        quickTime.value = value as NSString
        return [common, quickTime]
    }

    private func uniqueOutputURL(
        sourceURL: URL,
        segment: ConversionSegment,
        segmentCount: Int,
        directory: URL
    ) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let suffix = segmentCount == 1 ? "_mitene" : String(format: "_mitene_%02d", segment.index + 1)
        let initial = directory.appendingPathComponent("\(base)\(suffix).mp4")
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }

        var candidateIndex = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base)\(suffix)_\(candidateIndex).mp4")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            candidateIndex += 1
        }
    }
}
