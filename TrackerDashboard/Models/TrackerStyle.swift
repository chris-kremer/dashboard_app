import SwiftUI

enum TrackerStyle {
    static let background = adaptive(0xF6F5F1, 0x151815)
    static let surface = adaptive(0xFFFFFF, 0x222722)
    static let ink = adaptive(0x25322E, 0xEDF1E9)
    static let accent = adaptive(0x426753, 0xB4CEB2)
    static let soft = adaptive(0xE7EEE3, 0x293B30)
    static let freeTime = adaptive(0xBF776D, 0xDC9C91)
    static let sleep = adaptive(0xA39CBE, 0xB8AFD0)
    static let life = adaptive(0x829EAF, 0x93AFC0)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        func components(_ hex: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255)
        }
#if os(iOS)
        return Color(uiColor: UIColor { traits in
            let (r, g, b) = components(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
#elseif os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = components(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
#else
        let (r, g, b) = components(light)
        return Color(red: Double(r), green: Double(g), blue: Double(b))
#endif
    }
}

