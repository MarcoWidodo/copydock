import AppKit
import Combine
import SwiftUI

enum DockPosition: String, CaseIterable, Identifiable {
    case bottom
    case top
    case left
    case right

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var isVertical: Bool { self == .left || self == .right }
}

enum DockBackgroundStyle: String, CaseIterable, Identifiable {
    case none
    case glass
    case solid

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "None"
        case .glass: return "Glass"
        case .solid: return "Solid"
        }
    }
}

enum SlotShape: String, CaseIterable, Identifiable {
    case bubbles
    case roundedSquares

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bubbles: return "Floating Bubbles"
        case .roundedSquares: return "Rounded Squares"
        }
    }
}

enum ColorPalettePreset: String, CaseIterable, Identifiable {
    case custom
    case midnight
    case graphite
    case ocean
    case forest
    case sunset
    case violet
    case rose

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var colors: (accent: String, slot: String, background: String)? {
        switch self {
        case .custom: return nil
        case .midnight: return ("#5B7CFA", "#24272E", "#171A21")
        case .graphite: return ("#A6B0C3", "#2E323A", "#17191E")
        case .ocean: return ("#38BDF8", "#123047", "#0B1F2E")
        case .forest: return ("#4ADE80", "#173A2A", "#0E241A")
        case .sunset: return ("#FB7185", "#4A252B", "#2B171B")
        case .violet: return ("#A78BFA", "#2E2347", "#191329")
        case .rose: return ("#FF7AA2", "#452735", "#26161F")
        }
    }
}

final class AppSettings: ObservableObject {
    private enum Key {
        static let position = "dockPosition"
        static let background = "dockBackground"
        static let shape = "slotShape"
        static let slotSize = "slotSize"
        static let opacity = "dockOpacity"
        static let accentHex = "accentHex"
        static let slotBaseHex = "slotBaseHex"
        static let backgroundHex = "backgroundHex"
        static let edgeSnapping = "edgeSnapping"
        static let hoverPreviews = "hoverPreviews"
        static let previewWidth = "previewWidth"
        static let previewHeight = "previewHeight"
        static let previewCharacterLimit = "previewCharacterLimit"
        static let maximumCaptureMegabytes = "maximumCaptureMegabytes"
    }

    private let defaults: UserDefaults

    @Published var position: DockPosition { didSet { defaults.set(position.rawValue, forKey: Key.position) } }
    @Published var backgroundStyle: DockBackgroundStyle { didSet { defaults.set(backgroundStyle.rawValue, forKey: Key.background) } }
    @Published var slotShape: SlotShape { didSet { defaults.set(slotShape.rawValue, forKey: Key.shape) } }
    @Published var slotSize: Double { didSet { defaults.set(slotSize, forKey: Key.slotSize) } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: Key.opacity) } }
    @Published var accentHex: String { didSet { defaults.set(accentHex, forKey: Key.accentHex) } }
    @Published var slotBaseHex: String { didSet { defaults.set(slotBaseHex, forKey: Key.slotBaseHex) } }
    @Published var backgroundHex: String { didSet { defaults.set(backgroundHex, forKey: Key.backgroundHex) } }
    @Published var edgeSnapping: Bool { didSet { defaults.set(edgeSnapping, forKey: Key.edgeSnapping) } }
    @Published var hoverPreviews: Bool { didSet { defaults.set(hoverPreviews, forKey: Key.hoverPreviews) } }
    @Published var previewWidth: Double { didSet { defaults.set(previewWidth, forKey: Key.previewWidth) } }
    @Published var previewHeight: Double { didSet { defaults.set(previewHeight, forKey: Key.previewHeight) } }
    @Published var previewCharacterLimit: Double { didSet { defaults.set(previewCharacterLimit, forKey: Key.previewCharacterLimit) } }
    @Published var maximumCaptureMegabytes: Double { didSet { defaults.set(maximumCaptureMegabytes, forKey: Key.maximumCaptureMegabytes) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        position = defaults.string(forKey: Key.position).flatMap(DockPosition.init(rawValue:)) ?? .bottom
        backgroundStyle = defaults.string(forKey: Key.background).flatMap(DockBackgroundStyle.init(rawValue:)) ?? .glass
        slotShape = defaults.string(forKey: Key.shape).flatMap(SlotShape.init(rawValue:)) ?? .roundedSquares
        let savedSize = defaults.double(forKey: Key.slotSize)
        slotSize = savedSize == 0 ? 70 : min(max(savedSize, 44), 86)
        let savedOpacity = defaults.double(forKey: Key.opacity)
        opacity = savedOpacity == 0 ? 0.96 : min(max(savedOpacity, 0.35), 1)
        accentHex = defaults.string(forKey: Key.accentHex) ?? "#5B7CFA"
        slotBaseHex = defaults.string(forKey: Key.slotBaseHex) ?? "#24272E"
        backgroundHex = defaults.string(forKey: Key.backgroundHex) ?? "#171A21"
        edgeSnapping = defaults.object(forKey: Key.edgeSnapping) as? Bool ?? true
        hoverPreviews = defaults.object(forKey: Key.hoverPreviews) as? Bool ?? true
        let savedPreviewWidth = defaults.double(forKey: Key.previewWidth)
        previewWidth = savedPreviewWidth == 0 ? 480 : min(max(savedPreviewWidth, 280), 720)
        let savedPreviewHeight = defaults.double(forKey: Key.previewHeight)
        previewHeight = savedPreviewHeight == 0 ? 360 : min(max(savedPreviewHeight, 180), 600)
        let savedCharacterLimit = defaults.double(forKey: Key.previewCharacterLimit)
        previewCharacterLimit = savedCharacterLimit == 0 ? 4_000 : min(max(savedCharacterLimit, 500), 10_000)
        let savedCaptureLimit = defaults.double(forKey: Key.maximumCaptureMegabytes)
        maximumCaptureMegabytes = savedCaptureLimit == 0 ? 20 : min(max(savedCaptureLimit, 5), 200)
    }

    var slotLength: CGFloat { CGFloat(slotSize) }
    var accentColor: NSColor { NSColor(hex: accentHex) ?? .systemIndigo }
    var slotBaseColor: NSColor { NSColor(hex: slotBaseHex) ?? NSColor(hex: "#24272E")! }
    var dockBackgroundColor: NSColor { NSColor(hex: backgroundHex) ?? NSColor(hex: "#171A21")! }
    var previewSize: NSSize { NSSize(width: previewWidth, height: previewHeight) }
    var previewTextLimit: Int { Int(previewCharacterLimit) }
    var maximumCaptureBytes: Int { Int(maximumCaptureMegabytes * 1_024 * 1_024) }
    var selectedPalette: ColorPalettePreset {
        ColorPalettePreset.allCases.first { preset in
            guard let colors = preset.colors else { return false }
            return colors.accent == accentHex.uppercased()
                && colors.slot == slotBaseHex.uppercased()
                && colors.background == backgroundHex.uppercased()
        } ?? .custom
    }

    func applyPalette(_ preset: ColorPalettePreset) {
        guard let colors = preset.colors else { return }
        accentHex = colors.accent
        slotBaseHex = colors.slot
        backgroundHex = colors.background
    }

    func resetToDefaults() {
        position = .bottom
        backgroundStyle = .glass
        slotShape = .roundedSquares
        slotSize = 70
        opacity = 0.96
        accentHex = "#5B7CFA"
        slotBaseHex = "#24272E"
        backgroundHex = "#171A21"
        edgeSnapping = true
        hoverPreviews = true
        previewWidth = 480
        previewHeight = 360
        previewCharacterLimit = 4_000
        maximumCaptureMegabytes = 20
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#5B7CFA" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
