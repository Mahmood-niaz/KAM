import Foundation
import UIKit

/// Crop suggestion returned by Claude
struct CropSuggestion {
    let x: CGFloat      // Left edge (0-1)
    let y: CGFloat      // Top edge (0-1)
    let width: CGFloat  // Width (0-1)
    let height: CGFloat // Height (0-1)
    let explanation: String

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Result from scene analysis - which photo to use and how to crop it
struct SceneAnalysisResult {
    let selectedPhotoIndex: Int  // 0, 1, or 2
    let crop: CropSuggestion
    let reason: String  // Why this photo was selected
}

/// Result from smart pan analysis - which image to use and how to crop it
struct SmartPanAnalysisResult {
    let selectedImage: UIImage
    let crop: CropSuggestion
    let reason: String
    let selectedPairIndex: Int  // Which subject/pair was selected
    let isTelephotoBest: Bool   // Whether 4x was better than 1x
}

/// Service for calling Claude API for aesthetic crop suggestions
final class ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private var apiKey: String?

    private init() {
        loadAPIKey()
    }

    private func loadAPIKey() {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["ANTHROPIC_API_KEY"] as? String else {
            print("Warning: Could not load API key from Secrets.plist")
            return
        }
        apiKey = key
    }

    /// Analyze an image and suggest the best crop for aesthetic composition
    func suggestCrop(for image: UIImage, aspectRatio: AspectRatio = .fourThree) async throws -> CropSuggestion {
        guard let apiKey = apiKey else {
            throw ClaudeAPIError.missingAPIKey
        }

        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw ClaudeAPIError.imageConversionFailed
        }
        let base64Image = imageData.base64EncodedString()

        // Build request
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let prompt = """
        Analyze this image and suggest the single best crop that would create the most aesthetically pleasing composition.

        Consider:
        - Rule of thirds placement
        - Leading lines
        - Subject emphasis
        - Balance and symmetry
        - Removing distracting elements at edges

        Return ONLY a JSON object in this exact format, nothing else:
        {
            "x": 0.1,
            "y": 0.15,
            "width": 0.8,
            "height": 0.7,
            "explanation": "Brief explanation of why this crop improves the composition"
        }

        Where x, y are the top-left corner as percentages (0-1) of the image dimensions, and width/height are the crop size as percentages.

        CRITICAL: The crop MUST maintain exactly \(aspectRatio.displayName) aspect ratio. For portrait orientation use \(aspectRatio.portraitRatioString), for landscape use \(aspectRatio.landscapeRatioString). DO NOT change the image orientation - if the image is portrait, return a portrait crop; if landscape, return a landscape crop.
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 300,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Claude API error: \(errorBody)")
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ClaudeAPIError.parseError
        }

        // Extract JSON from response (Claude might wrap it in markdown)
        let cropSuggestion = try parseCropSuggestion(from: text)
        return cropSuggestion
    }

    /// Analyze multiple photos from a scene capture and return the best one with crop suggestion
    func analyzeScene(photos: [UIImage], aspectRatio: AspectRatio = .fourThree) async throws -> SceneAnalysisResult {
        guard let apiKey = apiKey else {
            throw ClaudeAPIError.missingAPIKey
        }

        guard photos.count >= 2 else {
            throw ClaudeAPIError.invalidPhotoCount
        }

        // Convert images to base64
        var imageContents: [[String: Any]] = []
        for (index, photo) in photos.enumerated() {
            guard let imageData = photo.jpegData(compressionQuality: 0.7) else {
                throw ClaudeAPIError.imageConversionFailed
            }
            let base64Image = imageData.base64EncodedString()

            imageContents.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64Image
                ]
            ])
        }

        // Build request
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let prompt = """
        I have \(photos.count) photos of the same scene taken from slightly different angles (panning left to right).

        Analyze all photos and determine:
        1. Which single photo has the best composition potential
        2. The optimal crop for that photo

        Consider:
        - Clean, uncluttered composition
        - Clear subject visibility
        - Aesthetic balance and visual appeal
        - Leading lines and rule of thirds
        - Absence of distracting elements

        Return ONLY a JSON object in this exact format, nothing else:
        {
            "selected_photo": 0,
            "reason": "Brief explanation of why this photo was selected over others",
            "crop": {
                "x": 0.1,
                "y": 0.15,
                "width": 0.8,
                "height": 0.7,
                "explanation": "Brief explanation of why this crop improves the composition"
            }
        }

        Where selected_photo is the index (0, 1, or 2) of the best photo.
        The crop x, y are the top-left corner as percentages (0-1), and width/height are the crop size as percentages.

        CRITICAL: The crop MUST maintain exactly \(aspectRatio.displayName) aspect ratio. For portrait orientation use \(aspectRatio.portraitRatioString), for landscape use \(aspectRatio.landscapeRatioString). DO NOT change the image orientation - if the image is portrait, return a portrait crop; if landscape, return a landscape crop.
        """

        // Add prompt as last content item
        var contentItems = imageContents
        contentItems.append([
            "type": "text",
            "text": prompt
        ])

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 500,
            "messages": [
                [
                    "role": "user",
                    "content": contentItems
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Claude API error: \(errorBody)")
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ClaudeAPIError.parseError
        }

        return try parseSceneAnalysisResult(from: text)
    }

    /// Analyze photo pairs from smart pan capture - each pair has 1x and 4x versions
    func analyzeSmartPanCaptures(pairs: [PhotoPair], aspectRatio: AspectRatio = .fourThree) async throws -> SmartPanAnalysisResult {
        guard let apiKey = apiKey else {
            throw ClaudeAPIError.missingAPIKey
        }

        guard !pairs.isEmpty else {
            throw ClaudeAPIError.invalidPhotoCount
        }

        // Build image contents - for each pair, add both 1x and 4x photos
        // Label them clearly so Claude knows which is which
        var imageContents: [[String: Any]] = []
        var imageLabels: [String] = []

        for (pairIndex, pair) in pairs.enumerated() {
            // Add 1x photo
            guard let wideData = pair.widePhoto.jpegData(compressionQuality: 0.7) else {
                throw ClaudeAPIError.imageConversionFailed
            }
            imageContents.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": wideData.base64EncodedString()
                ]
            ])
            imageLabels.append("Subject \(pairIndex + 1) at 1x (wide)")

            // Add 4x photo
            guard let teleData = pair.telephotoPhoto.jpegData(compressionQuality: 0.7) else {
                throw ClaudeAPIError.imageConversionFailed
            }
            imageContents.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": teleData.base64EncodedString()
                ]
            ])
            imageLabels.append("Subject \(pairIndex + 1) at 4x (telephoto)")
        }

        // Build request
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let imageDescriptions = imageLabels.enumerated().map { "Image \($0.offset): \($0.element)" }.joined(separator: "\n")

        let prompt = """
        I have \(pairs.count) subjects detected during a camera pan, each captured at both 1x (wide) and 4x (telephoto) zoom levels.

        Image order:
        \(imageDescriptions)

        Analyze ALL images and select the SINGLE BEST image for aesthetic cropping.

        Consider:
        - Subject clarity and detail
        - Composition potential
        - Whether 1x context or 4x detail works better for each subject
        - Overall aesthetic appeal
        - Clean backgrounds and minimal distractions

        Return ONLY a JSON object in this exact format, nothing else:
        {
            "selected_image_index": 0,
            "selected_pair_index": 0,
            "is_telephoto": false,
            "reason": "Brief explanation of why this specific image was selected",
            "crop": {
                "x": 0.1,
                "y": 0.15,
                "width": 0.8,
                "height": 0.7,
                "explanation": "Brief explanation of why this crop improves the composition"
            }
        }

        Where selected_image_index is the 0-based index in the image list above.
        selected_pair_index is which subject (0-based).
        is_telephoto is true if the 4x version was selected, false if 1x.

        CRITICAL: The crop MUST maintain exactly \(aspectRatio.displayName) aspect ratio. For portrait orientation use \(aspectRatio.portraitRatioString), for landscape use \(aspectRatio.landscapeRatioString). DO NOT change the image orientation.
        """

        var contentItems = imageContents
        contentItems.append([
            "type": "text",
            "text": prompt
        ])

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 600,
            "messages": [
                [
                    "role": "user",
                    "content": contentItems
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Claude API error: \(errorBody)")
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ClaudeAPIError.parseError
        }

        return try parseSmartPanResult(from: text, pairs: pairs)
    }

    private func parseSmartPanResult(from text: String, pairs: [PhotoPair]) throws -> SmartPanAnalysisResult {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.contains("```") {
            let pattern = "```(?:json)?\\s*([\\s\\S]*?)```"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
               let range = Range(match.range(at: 1), in: jsonString) {
                jsonString = String(jsonString[range])
            }
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selectedPairIndex = json["selected_pair_index"] as? Int,
              let isTelephoto = json["is_telephoto"] as? Bool,
              let cropJson = json["crop"] as? [String: Any],
              let x = cropJson["x"] as? Double,
              let y = cropJson["y"] as? Double,
              let width = cropJson["width"] as? Double,
              let height = cropJson["height"] as? Double else {
            throw ClaudeAPIError.parseError
        }

        let reason = json["reason"] as? String ?? "Best composition"
        let cropExplanation = cropJson["explanation"] as? String ?? "Improved composition"

        // Get the selected image
        let safePairIndex = min(selectedPairIndex, pairs.count - 1)
        let selectedImage = isTelephoto ? pairs[safePairIndex].telephotoPhoto : pairs[safePairIndex].widePhoto

        let crop = CropSuggestion(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height),
            explanation: cropExplanation
        )

        return SmartPanAnalysisResult(
            selectedImage: selectedImage,
            crop: crop,
            reason: reason,
            selectedPairIndex: safePairIndex,
            isTelephotoBest: isTelephoto
        )
    }

    private func parseSceneAnalysisResult(from text: String) throws -> SceneAnalysisResult {
        // Try to extract JSON from the response
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.contains("```") {
            let pattern = "```(?:json)?\\s*([\\s\\S]*?)```"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
               let range = Range(match.range(at: 1), in: jsonString) {
                jsonString = String(jsonString[range])
            }
        }

        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selectedPhoto = json["selected_photo"] as? Int,
              let cropJson = json["crop"] as? [String: Any],
              let x = cropJson["x"] as? Double,
              let y = cropJson["y"] as? Double,
              let width = cropJson["width"] as? Double,
              let height = cropJson["height"] as? Double else {
            throw ClaudeAPIError.parseError
        }

        let reason = json["reason"] as? String ?? "Best composition"
        let cropExplanation = cropJson["explanation"] as? String ?? "Improved composition"

        let crop = CropSuggestion(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height),
            explanation: cropExplanation
        )

        return SceneAnalysisResult(
            selectedPhotoIndex: selectedPhoto,
            crop: crop,
            reason: reason
        )
    }

    private func parseCropSuggestion(from text: String) throws -> CropSuggestion {
        // Try to extract JSON from the response (might be wrapped in ```json blocks)
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.contains("```") {
            let pattern = "```(?:json)?\\s*([\\s\\S]*?)```"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
               let range = Range(match.range(at: 1), in: jsonString) {
                jsonString = String(jsonString[range])
            }
        }

        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let x = json["x"] as? Double,
              let y = json["y"] as? Double,
              let width = json["width"] as? Double,
              let height = json["height"] as? Double else {
            throw ClaudeAPIError.parseError
        }

        let explanation = json["explanation"] as? String ?? "Improved composition"

        return CropSuggestion(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height),
            explanation: explanation
        )
    }
}

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case imageConversionFailed
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case invalidPhotoCount

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not found. Add your key to Secrets.plist"
        case .imageConversionFailed:
            return "Failed to convert image for upload"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .parseError:
            return "Failed to parse crop suggestion from response"
        case .invalidPhotoCount:
            return "Scene capture requires at least 2 photos"
        }
    }
}
