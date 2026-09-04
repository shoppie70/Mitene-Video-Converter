import XCTest
@testable import MiteneVideoConverter

final class VideoConverterErrorTests: XCTestCase {
    func testExportFailedContainsDetailedReason() {
        let error = VideoConverterError.exportFailed("ディスクに空きがありません")
        XCTAssertEqual(error.errorDescription, "動画の変換に失敗しました: ディスクに空きがありません")
    }

    func testExportFailedWithEmptyReason() {
        let error = VideoConverterError.exportFailed("")
        XCTAssertEqual(error.errorDescription, "動画の変換に失敗しました。")
    }

    func testInsufficientStorageContainsAvailableAndRequiredMB() {
        let error = VideoConverterError.insufficientStorage(availableMB: 134, requiredMB: 200)
        XCTAssertEqual(
            error.errorDescription,
            "保存先の空き容量が足りません（空き: 約134MB / 必要目安: 約200MB）。ディスクの空き容量を確保してください。"
        )
    }

    func testOtherErrorDescriptions() {
        XCTAssertEqual(
            VideoConverterError.unreadableVideo.errorDescription,
            "動画を正常に読み込めませんでした。ファイルが壊れているか、対応していない形式の可能性があります。"
        )
        XCTAssertEqual(
            VideoConverterError.noVideoTrack.errorDescription,
            "この動画のフォーマットはサポートされていないか、映像トラックがありません。"
        )
        XCTAssertEqual(
            VideoConverterError.unsupportedVideo.errorDescription,
            "この動画のフォーマットはサポートされていないか、映像トラックがありません。"
        )
        XCTAssertEqual(
            VideoConverterError.photoLibraryAccessDenied.errorDescription,
            "写真アプリへのアクセスが許可されていません。"
        )
    }

    func testEvaluateStorageThrowsWhenSpaceIsInsufficient() {
        // 229秒（約3分49秒）の動画: 229 * 0.6 + 50 = 187MB必要
        let availableBytes: Int64 = 134 * 1024 * 1024 // 134MB
        XCTAssertThrowsError(try VideoConverter.evaluateStorage(availableBytes: availableBytes, duration: 229.0)) { error in
            guard let converterError = error as? VideoConverterError else {
                return XCTFail("Expected VideoConverterError")
            }
            if case .insufficientStorage(let availableMB, let requiredMB) = converterError {
                XCTAssertEqual(availableMB, 134)
                XCTAssertEqual(requiredMB, 188)
            } else {
                XCTFail("Expected insufficientStorage, got \(converterError)")
            }
        }
    }

    func testEvaluateStoragePassesWhenSpaceIsSufficient() {
        let availableBytes: Int64 = 1000 * 1024 * 1024 // 1000MB
        XCTAssertNoThrow(try VideoConverter.evaluateStorage(availableBytes: availableBytes, duration: 229.0))
    }
}

