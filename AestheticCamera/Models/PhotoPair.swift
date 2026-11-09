import Foundation
import UIKit

/// A pair of photos captured at 1x and 4x zoom of the same subject
struct PhotoPair: Identifiable {
    let id = UUID()
    let subject: DetectedSubject     // The detected subject this pair is for
    let widePhoto: UIImage           // 1x capture
    let telephotoPhoto: UIImage      // 4x capture
    let captureTime: Date

    init(subject: DetectedSubject, widePhoto: UIImage, telephotoPhoto: UIImage) {
        self.subject = subject
        self.widePhoto = widePhoto
        self.telephotoPhoto = telephotoPhoto
        self.captureTime = Date()
    }
}
