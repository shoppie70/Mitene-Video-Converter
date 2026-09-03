import Foundation
import Photos

@MainActor
final class PhotoLibraryExporter {
    func add(urls: [URL]) async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        if current == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            status = current
        }
        guard status == .authorized || status == .limited else {
            throw VideoConverterError.photoLibraryAccessDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                urls.forEach { _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: $0) }
            }) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? VideoConverterError.exportFailed("Photo import failed"))
                }
            }
        }
    }
}
