import Foundation

/// State machine for smart panning capture mode
enum SmartPanState: Equatable {
    case idle                          // Not active
    case panning                       // Actively panning, looking for subjects
    case subjectDetected               // Subject found, preparing to capture
    case capturingWide                 // Capturing 1x photo
    case switchingToTelephoto          // Switching from 1x to 4x lens
    case capturingTelephoto            // Capturing 4x photo
    case switchingBackToWide           // Switching back to 1x for continued panning
    case processing                    // All captures done, sending to Claude

    var isCapturing: Bool {
        switch self {
        case .capturingWide, .capturingTelephoto:
            return true
        default:
            return false
        }
    }

    var isSwitchingLens: Bool {
        switch self {
        case .switchingToTelephoto, .switchingBackToWide:
            return true
        default:
            return false
        }
    }

    var shouldShowHoldStill: Bool {
        switch self {
        case .subjectDetected, .capturingWide, .switchingToTelephoto, .capturingTelephoto:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Start panning"
        case .panning:
            return "Pan slowly to find subjects"
        case .subjectDetected:
            return "Subject detected!"
        case .capturingWide:
            return "Capturing 1x..."
        case .switchingToTelephoto:
            return "Switching to 4x..."
        case .capturingTelephoto:
            return "Capturing 4x..."
        case .switchingBackToWide:
            return "Resuming scan..."
        case .processing:
            return "Analyzing photos..."
        }
    }
}
