import Foundation
import CoreGraphics

/// Represents a subject detected during smart panning
struct DetectedSubject: Identifiable {
    let id = UUID()
    let yawAngle: Double         // Device yaw angle when subject was detected (radians)
    let timestamp: Date          // When the subject was detected
    let saliencyCenter: CGPoint  // Center of saliency (0-1 normalized)
    let confidence: Float        // Detection confidence (0-1)

    /// Check if another detection is likely the same subject (within yaw tolerance)
    func isDuplicate(of other: DetectedSubject, yawTolerance: Double = 0.148) -> Bool {
        // 8.5 degrees in radians = ~0.148
        return abs(yawAngle - other.yawAngle) < yawTolerance
    }

    /// Check if a yaw angle represents the same region as this subject
    func isInSameRegion(yaw: Double, tolerance: Double = 0.148) -> Bool {
        return abs(yawAngle - yaw) < tolerance
    }
}
