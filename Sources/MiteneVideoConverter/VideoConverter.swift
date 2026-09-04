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
        try checkAvailableStorage(for: outputDirectory, duration: analysis.duration)

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
                    let detailedMessage = Self.describe(exportError: error)
                    continuation.resume(throwing: VideoConverterError.exportFailed(detailedMessage))
                } else {
                    continuation.resume(throwing: VideoConverterError.exportFailed("エクスポート処理が予期せず終了しました"))
                }
            }
        }
    }

    private func checkAvailableStorage(for directory: URL, duration: Double) throws {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let available = values?.volumeAvailableCapacity else { return }
        try Self.evaluateStorage(availableBytes: Int64(available), duration: duration)
    }

    nonisolated static func estimateRequiredStorageMB(duration: Double) -> Int {
        max(100, Int(ceil(duration * 0.6)) + 50)
    }

    nonisolated static func evaluateStorage(availableBytes: Int64, duration: Double) throws {
        let availableMB = max(0, Int(availableBytes / (1024 * 1024)))
        let estimatedRequiredMB = estimateRequiredStorageMB(duration: duration)
        if availableMB < estimatedRequiredMB {
            throw VideoConverterError.insufficientStorage(availableMB: availableMB, requiredMB: estimatedRequiredMB)
        }
    }

    private nonisolated static func describe(exportError: Error) -> String {
        let nsError = exportError as NSError
        if nsError.domain == AVFoundationErrorDomain, nsError.code == AVError.diskFull.rawValue {
            return "ディスクの空き容量が不足しています"
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            if underlying.domain == NSPOSIXErrorDomain && underlying.code == ENOSPC {
                return "ディスクの空き容量が不足しています"
            }
            if underlying.domain == AVFoundationErrorDomain && underlying.code == AVError.diskFull.rawValue {
                return "ディスクの空き容量が不足しています"
            }
            return "\(nsError.localizedDescription) (\(underlying.localizedDescription))"
        }
        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            return "\(nsError.localizedDescription): \(failureReason)"
        }
        return nsError.localizedDescription
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
