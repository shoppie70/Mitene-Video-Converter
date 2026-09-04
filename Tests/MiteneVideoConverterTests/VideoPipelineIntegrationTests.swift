import AVFoundation
import XCTest
@testable import MiteneVideoConverter

@MainActor
final class VideoPipelineIntegrationTests: XCTestCase {
    func testRealMovieIsAnalyzedAndConvertedToMp4() async throws {
        guard Self.ffmpegURL != nil else {
            throw XCTSkip("ffmpeg is required for the local pipeline smoke test")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mitene-pipeline-\(UUID().uuidString)", isDirectory: true)
        let inputURL = root.appendingPathComponent("sample.mov")
        let outputDirectory = root.appendingPathComponent("output", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.makeFixture(at: inputURL)

        let analysis = try await VideoAnalyzer().analyze(url: inputURL)
        let plan = ConversionPlanner().plan(for: analysis)
        let outputs = try await VideoConverter().convert(
            analysis: analysis,
            plan: plan,
            outputDirectory: outputDirectory,
            progress: { _ in }
        )

        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputs[0].path))

        let outputAsset = AVURLAsset(url: outputs[0])
        let outputDuration = CMTimeGetSeconds(try await outputAsset.load(.duration))
        let outputTracks = try await outputAsset.load(.tracks)
        let outputVideo = try XCTUnwrap(outputTracks.first(where: { $0.mediaType == .video }))
        let outputSize = try await outputVideo.load(.naturalSize)
        let outputFrameRate = try await outputVideo.load(.nominalFrameRate)
        let outputDescriptions = try await outputVideo.load(.formatDescriptions)
        let outputDescription = try XCTUnwrap(outputDescriptions.first)
        let outputMetadata = try await outputAsset.load(.metadata)

        XCTAssertLessThan(outputDuration, 120)
        XCTAssertEqual(Int(round(outputSize.width)), 640)
        XCTAssertEqual(Int(round(outputSize.height)), 360)
        XCTAssertLessThanOrEqual(outputFrameRate, 30)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(outputDescription), kCMVideoCodecType_H264)
        XCTAssertTrue(outputTracks.contains { $0.mediaType == .audio })
        XCTAssertTrue(
            outputMetadata.contains { $0.identifier == .commonIdentifierCreationDate || $0.identifier?.rawValue == "uiso/date" },
            outputMetadata.map { $0.identifier?.rawValue ?? "nil" }.joined(separator: ", ")
        )
    }

    func testMultiSegmentMovieIsConvertedWithoutVideoCompositionError() async throws {
        guard Self.ffmpegURL != nil else {
            throw XCTSkip("ffmpeg is required for the local pipeline smoke test")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mitene-multi-pipeline-\(UUID().uuidString)", isDirectory: true)
        let inputURL = root.appendingPathComponent("sample.mov")
        let outputDirectory = root.appendingPathComponent("output", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.makeFixture(at: inputURL)

        let analysis = try await VideoAnalyzer().analyze(url: inputURL)
        // 1秒の動画を2分割（0〜0.5秒、0.5〜1.0秒）するプランを作成して start > 0 のセグメント変換をテスト
        let plan = ConversionPlan(
            outputSize: VideoSize(width: 640, height: 360),
            outputFrameRate: 30,
            segments: [
                ConversionSegment(index: 0, start: 0, duration: 0.5, creationDate: analysis.creationDate),
                ConversionSegment(index: 1, start: 0.5, duration: 0.5, creationDate: analysis.creationDate.addingTimeInterval(0.5)),
            ]
        )

        let outputs = try await VideoConverter().convert(
            analysis: analysis,
            plan: plan,
            outputDirectory: outputDirectory,
            progress: { _ in }
        )

        XCTAssertEqual(outputs.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputs[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputs[1].path))
    }

    private static var ffmpegURL: URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        return candidates.lazy.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func makeFixture(at outputURL: URL) throws {
        guard let ffmpegURL else { throw XCTSkip("ffmpeg is required for the local pipeline smoke test") }
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=640x360:rate=30",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000",
            "-t", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-y", outputURL.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "MiteneVideoConverterTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg could not create a fixture"])
        }
    }
}
