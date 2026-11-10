import Photos
import UIKit

final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private init() {}

    /// Saves the original encoded photo data (as delivered by AVCapturePhoto) without re-encoding,
    /// so the Photos app receives the full sensor resolution and original metadata.
    func savePhoto(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                let error = NSError(domain: "PhotoLibraryService", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false

                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: data, options: options)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                    } else if success {
                        completion(.success(()))
                    } else {
                        let unknownError = NSError(domain: "PhotoLibraryService", code: 2,
                                                  userInfo: [NSLocalizedDescriptionKey: "Unknown error saving photo"])
                        completion(.failure(unknownError))
                    }
                }
            }
        }
    }
}
