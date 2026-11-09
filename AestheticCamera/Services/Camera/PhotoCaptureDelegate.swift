import Photos
import UIKit

final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    private init() {}

    func savePhoto(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                let error = NSError(domain: "PhotoLibraryService", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            // Convert to maximum quality JPEG data
            guard let jpegData = image.jpegData(compressionQuality: 1.0) else {
                let error = NSError(domain: "PhotoLibraryService", code: 3,
                                   userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false

                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: jpegData, options: options)
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
