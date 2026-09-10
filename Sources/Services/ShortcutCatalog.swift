import AppKit
import Carbon

extension ShortcutService {
    enum Scope: Int { case global, image, video }

    enum Group: String, CaseIterable {
        case general
        case screenshots
        case ocr
        case recording
        case preview
        case imageTools
        case imageEditing
        case videoEditing

        var title: String {
            switch self {
            case .general: "General"
            case .screenshots: "Screenshots"
            case .ocr: "OCR & Color"
            case .recording: "Screen Recording"
            case .preview: "Capture Deck"
            case .imageTools: "Image Tools"
            case .imageEditing: "Image Editing"
            case .videoEditing: "Video Editing"
            }
        }
    }

    // Persisted IDs must never be renumbered. New actions start unassigned.
    enum Action: UInt32, CaseIterable {
        case recording = 6
        case mediaGallery = 10
        case restoreLastCapture = 11
        case pinLastCapture = 12
        case openImage = 13
        case openSettings = 14
        // 15 is reserved: onboarding is available only during initial setup.
        case unpinAll = 16
        case region = 1
        case fullscreen = 2
        case window = 3
        case previousRegion = 20
        case timedRegion = 21
        case regionCopy = 22
        case regionSave = 23
        case regionEdit = 24
        case regionPin = 25
        case ocr = 4
        case ocrSingleLine = 30
        case colorPicker = 5
        case recordingOptions = 7
        case recordArea = 40
        case stopRecording = 41
        case pauseRecording = 42
        case restartRecording = 43
        case discardRecording = 44
        case togglePreviews = 50
        case savePreviews = 51
        case closePreviews = 52
        case imageBackground = 100
        case imageSelect = 101
        case imageCrop = 102
        case imageRectangle = 103
        case imageFilledRectangle = 104
        case imageEllipse = 105
        case imageLine = 106
        case imageArrow = 107
        case imageFreehand = 108
        case imageCounter = 109
        case imageText = 110
        case imageHighlight = 111
        case imagePixelate = 112
        case imageBlur = 113
        case imageSave = 120
        case imageExport = 121
        case imageCopy = 122
        case imageShare = 123
        case imageUndo = 124
        case imageRedo = 125
        case imageSelectAll = 126
        case imageDelete = 127
        case imageZoomIn = 128
        case imageZoomOut = 129
        case imageFit = 130
        case imageActualSize = 131
        case imageIncreaseSize = 132
        case imageDecreaseSize = 133
        case videoSave = 200
        case videoExport = 201
        case videoShare = 202
        case videoPlay = 203
        case videoStart = 204
        case videoEnd = 205
        case videoSplitTool = 206
        case videoCut = 207
        case videoDelete = 208
        case videoUndo = 209
        case videoRedo = 210
        case videoZoomIn = 211
        case videoZoomOut = 212
        case videoFit = 213
        case videoCrop = 214
        case videoBlur = 215
        case videoPixelate = 216
        case videoInspector = 217
        case videoAddZoom = 218

        var title: String {
            switch self {
            case .recording: "Capture & Recording Bar"
            case .mediaGallery: "Open Media Gallery"
            case .restoreLastCapture: "Restore Last Capture"
            case .pinLastCapture: "Pin Last Capture"
            case .openImage: "Open Image from File"
            case .openSettings: "Open Settings"
            case .unpinAll: "Unpin All Captures"
            case .region: "Capture Region"
            case .fullscreen: "Capture Fullscreen"
            case .window: "Capture Window"
            case .previousRegion: "Capture Previous Region"
            case .timedRegion: "Capture Region with Timer"
            case .regionCopy: "Capture Region & Copy"
            case .regionSave: "Capture Region & Save"
            case .regionEdit: "Capture Region & Annotate"
            case .regionPin: "Capture Region & Pin"
            case .ocr: "Capture Text"
            case .ocrSingleLine: "Capture Text without Line Breaks"
            case .colorPicker: "Pick Color"
            case .recordingOptions: "Recording Options"
            case .recordArea: "Record Area"
            case .stopRecording: "Stop & Save Recording"
            case .pauseRecording: "Pause / Resume Recording"
            case .restartRecording: "Restart Recording"
            case .discardRecording: "Discard Recording"
            case .togglePreviews: "Hide / Show Capture Deck"
            case .savePreviews: "Save All Captures in Deck"
            case .closePreviews: "Close All Captures in Deck"
            case .imageBackground: "Background Inspector"
            case .imageSelect: "Select / Move Tool"
            case .imageCrop: "Crop Tool"
            case .imageRectangle: "Rectangle Tool"
            case .imageFilledRectangle: "Filled Rectangle Tool"
            case .imageEllipse: "Ellipse Tool"
            case .imageLine: "Line Tool"
            case .imageArrow: "Arrow Tool"
            case .imageFreehand: "Draw Tool"
            case .imageCounter: "Counter Tool"
            case .imageText: "Text Tool"
            case .imageHighlight: "Highlight / Spotlight Tool"
            case .imagePixelate: "Pixelate Tool"
            case .imageBlur: "Blur Tool"
            case .imageSave: "Save Edits"
            case .imageExport: "Export Image / Save As"
            case .imageCopy: "Copy Screenshot to Clipboard"
            case .imageShare: "Share to Cloud"
            case .imageUndo: "Undo"
            case .imageRedo: "Redo"
            case .imageSelectAll: "Select All Objects"
            case .imageDelete: "Delete Selected Objects"
            case .imageZoomIn: "Zoom In"
            case .imageZoomOut: "Zoom Out"
            case .imageFit: "Fit Canvas"
            case .imageActualSize: "Actual Size"
            case .imageIncreaseSize: "Increase Tool Size"
            case .imageDecreaseSize: "Decrease Tool Size"
            case .videoSave: "Save Project"
            case .videoExport: "Export Video"
            case .videoShare: "Share to Cloud"
            case .videoPlay: "Play / Pause"
            case .videoStart: "Go to Start"
            case .videoEnd: "Go to End"
            case .videoSplitTool: "Scissors Tool"
            case .videoCut: "Cut at Playhead / Hover"
            case .videoDelete: "Delete Selection"
            case .videoUndo: "Undo"
            case .videoRedo: "Redo"
            case .videoZoomIn: "Zoom In Timeline"
            case .videoZoomOut: "Zoom Out Timeline"
            case .videoFit: "Fit Timeline"
            case .videoCrop: "Crop Video"
            case .videoBlur: "Blur Mask"
            case .videoPixelate: "Pixelate Mask"
            case .videoInspector: "Show / Hide Inspector"
            case .videoAddZoom: "Add Zoom at Playhead"
            }
        }

        var group: Group {
            switch self {
            case .recording, .mediaGallery, .restoreLastCapture, .pinLastCapture, .openImage, .openSettings, .unpinAll: .general
            case .region, .fullscreen, .window, .previousRegion, .timedRegion, .regionCopy, .regionSave, .regionEdit, .regionPin: .screenshots
            case .ocr, .ocrSingleLine, .colorPicker: .ocr
            case .recordingOptions, .recordArea, .stopRecording, .pauseRecording, .restartRecording, .discardRecording: .recording
            case .togglePreviews, .savePreviews, .closePreviews: .preview
            case .imageBackground, .imageSelect, .imageCrop, .imageRectangle, .imageFilledRectangle, .imageEllipse, .imageLine, .imageArrow, .imageFreehand, .imageCounter, .imageText, .imageHighlight, .imagePixelate, .imageBlur: .imageTools
            case .imageSave, .imageExport, .imageCopy, .imageShare, .imageUndo, .imageRedo, .imageSelectAll, .imageDelete, .imageZoomIn, .imageZoomOut, .imageFit, .imageActualSize, .imageIncreaseSize, .imageDecreaseSize: .imageEditing
            case .videoSave, .videoExport, .videoShare, .videoPlay, .videoStart, .videoEnd, .videoSplitTool, .videoCut, .videoDelete, .videoUndo, .videoRedo, .videoZoomIn, .videoZoomOut, .videoFit, .videoCrop, .videoBlur, .videoPixelate, .videoInspector, .videoAddZoom: .videoEditing
            }
        }

        var scope: Scope {
            switch group {
            case .imageTools, .imageEditing: .image
            case .videoEditing: .video
            default: .global
            }
        }

        var defaultShortcut: Shortcut? {
            switch self {
            case .region: .defaultRegion
            case .fullscreen: .defaultFullscreen
            case .ocr: .defaultOCR
            case .colorPicker: .defaultColorPicker
            case .recording: .defaultRecording
            case .recordingOptions: .defaultRecordingOptions
            case .imageSelect: Shortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(0), enabled: true)
            case .imageCrop: Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(0), enabled: true)
            case .imageRectangle: Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(0), enabled: true)
            case .imageEllipse: Shortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(0), enabled: true)
            case .imageLine: Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(0), enabled: true)
            case .imageArrow: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(0), enabled: true)
            case .imageCounter: Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(0), enabled: true)
            case .imageText: Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(0), enabled: true)
            case .imagePixelate: Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(0), enabled: true)
            case .imageBlur: Shortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(0), enabled: true)
            case .imageSave: Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey), enabled: true)
            case .imageCopy: Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
            case .imageUndo: Shortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey), enabled: true)
            case .imageRedo: Shortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
            case .imageSelectAll: Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey), enabled: true)
            case .imageDelete: Shortcut(keyCode: UInt32(kVK_Delete), modifiers: UInt32(0), enabled: true)
            case .imageZoomIn: Shortcut(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(cmdKey), enabled: true)
            case .imageZoomOut: Shortcut(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(cmdKey), enabled: true)
            case .imageFit: Shortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey), enabled: true)
            case .imageActualSize: Shortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: UInt32(cmdKey), enabled: true)
            case .videoSave: Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey), enabled: true)
            case .videoPlay: Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(0), enabled: true)
            case .videoSplitTool: Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(0), enabled: true)
            case .videoCut: Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(0), enabled: true)
            case .videoDelete: Shortcut(keyCode: UInt32(kVK_Delete), modifiers: UInt32(0), enabled: true)
            case .videoUndo: Shortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey), enabled: true)
            case .videoRedo: Shortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(cmdKey | shiftKey), enabled: true)
            case .videoZoomIn: Shortcut(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt32(cmdKey), enabled: true)
            case .videoZoomOut: Shortcut(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt32(cmdKey), enabled: true)
            case .videoFit: Shortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: UInt32(cmdKey), enabled: true)
            default: nil
            }
        }

        var annotationTool: AnnotationTool? {
            switch self {
            case .imageSelect: .select
            case .imageRectangle: .rectangle
            case .imageFilledRectangle: .filledRectangle
            case .imageEllipse: .ellipse
            case .imageLine: .line
            case .imageArrow: .arrow
            case .imageFreehand: .freehand
            case .imageCounter: .numberedCircle
            case .imageText: .text
            case .imageHighlight: .highlight
            case .imagePixelate: .pixelate
            case .imageBlur: .blur
            default: nil
            }
        }
    }
}
