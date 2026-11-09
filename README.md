# KAM (Aesthetic Camera)

[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-orange)](#requirements)
[![Visibility](https://img.shields.io/badge/repo-public-brightgreen)](#)

An iOS camera app that scores framing in real time and uses Claude AI to pick the strongest shot and crop. The app keeps your photos on the device and only sends images to Claude when you ask for a crop suggestion.

## Highlights

- **Live feedback:** composition scores update as you frame the shot, with directional hints ("move left") and a subject highlight.
- **Best-shot selection:** Smart Pan captures wide and telephoto pairs as you move, and Claude chooses the best one.
- **Crops that respect your ratio:** Claude's suggestions are constrained to the aspect ratio you pick.
- **Hands-free capture:** auto-capture fires once the composition score passes your threshold.

## Features

- **Real-time Composition Scoring**: Analyzes rule of thirds, golden ratio, leading lines, and overall aesthetic quality
- **Smart Pan Mode**: Auto-detects subjects via saliency analysis, captures at both 1x and 4x zoom, sends to Claude AI to select the best shot
- **Scene Capture Mode**: Pan and capture multiple angles, AI selects the best composition
- **Claude AI Crop Suggestions**: Get intelligent crop recommendations with enforced aspect ratios
- **Aspect Ratio Selection**: Choose from 4:3, 16:9, 1:1, or 3:2 ratios
- **Auto-Capture**: Automatically captures when composition score exceeds threshold
- **Composition Guides**: Visual hints for improving framing

## Requirements

- iOS 17.0+
- Xcode 15.0+
- iPhone with camera (Pro models recommended for multi-lens features)
- Anthropic API key for Claude AI features

## Build Instructions

1. Clone the repository:
   ```bash
   git clone https://github.com/Mahmood-niaz/KAM.git
   cd KAM
   ```

2. Create `Secrets.plist` in the `AestheticCamera/` directory:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>ANTHROPIC_API_KEY</key>
       <string>your-api-key-here</string>
   </dict>
   </plist>
   ```

3. Open `AestheticCamera.xcodeproj` in Xcode

4. Select your development team in Signing & Capabilities

5. Build and run on a physical device (camera features require real hardware)

## Version History

### Version 4 (Current)
**Smart pan mode, aspect ratio selection, and bug fixes**

- **Smart Pan Mode**: New capture mode that auto-detects subjects via saliency analysis during panning. When a subject is detected (with ~8.5° yaw deduplication to avoid duplicates), triggers haptic feedback and captures at both 1x (wide) and 4x (telephoto). All photo pairs are sent to Claude to select the best image and crop.
- **Aspect Ratio Selector**: Added settings option to choose crop aspect ratio (4:3, 16:9, 1:1, 3:2). Claude prompts now enforce the selected ratio.
- **Bug Fixes**:
  - Fixed landscape photos saving with incorrect orientation
  - Added `NSPhotoLibraryUsageDescription` for gallery read access
  - Created app icon (camera aperture design)
- **Changes**:
  - Removed 0.5x ultra-wide lens option (now starts at 1x)
  - New models: `AspectRatio`, `DetectedSubject`, `PhotoPair`, `SmartPanState`
  - New `SmartPanController` for motion tracking and capture sequencing

### Version 3
**Claude AI crop suggestions and camera lens fixes**

- Added Claude API integration for intelligent crop suggestions
- Single shot mode: capture photo, request AI crop recommendation
- Scene capture mode: pan to capture 3 angles, AI selects best shot and crop
- Crop preview UI with accept/reject workflow
- Fixed camera lens switching and zoom factors for triple-camera iPhones

### Version 2
**Improved composition guidance and UI**

- Added `CompositionGuide` system with directional hints (move left/right/up/down)
- Lens suggestions based on subject size
- Visual subject highlight overlay
- Stability logic to prevent rapid hint changes
- Score smoothing with exponential moving average

### Version 1
**Initial release with NIMA integration**

- Real-time composition analysis using Vision framework
- Rule of thirds, golden ratio, and leading lines detection
- NIMA-based aesthetic quality scoring
- Auto-capture with configurable threshold
- Grid overlays (rule of thirds, golden ratio, diagonal)
- Basic settings UI

## Project Structure

```
AestheticCamera/
├── Models/
│   ├── AspectRatio.swift       # Aspect ratio enum (4:3, 16:9, 1:1, 3:2)
│   ├── CameraLens.swift        # Lens options (1x, 2x, 4x, 8x)
│   ├── CompositionGuide.swift  # Directional composition hints
│   ├── CompositionScore.swift  # Scoring data structure
│   ├── DetectedSubject.swift   # Subject tracking with yaw angle
│   ├── PhotoPair.swift         # 1x + 4x photo pair
│   └── SmartPanState.swift     # Smart pan state machine
├── Services/
│   ├── AI/
│   │   └── ClaudeAPIService.swift    # Claude API integration
│   ├── AutoCapture/
│   │   ├── AutoCaptureController.swift
│   │   └── MotionAnalyzer.swift
│   ├── Camera/
│   │   ├── CameraService.swift       # AVFoundation camera control
│   │   ├── PhotoCaptureDelegate.swift
│   │   ├── SceneCaptureController.swift
│   │   └── SmartPanController.swift  # Motion + saliency subject detection
│   └── Composition/
│       ├── CompositionEngine.swift
│       ├── CompositionGuideAnalyzer.swift
│       ├── GoldenRatioAnalyzer.swift
│       ├── LeadingLinesAnalyzer.swift
│       ├── NIMAScorer.swift
│       ├── RuleOfThirdsAnalyzer.swift
│       └── SaliencyAnalyzer.swift
├── ViewModels/
│   └── CameraViewModel.swift
└── Views/
    ├── Camera/
    ├── CropPreview/
    ├── Gallery/
    ├── Overlays/
    ├── SceneCapture/
    └── Settings/
```

## License

Private project.
