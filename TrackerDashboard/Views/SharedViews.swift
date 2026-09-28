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
#else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = components(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
#endif
    }
}

struct TrackerSectionHeader: View {
    let title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.bold))
            Spacer(minLength: 8)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }
    }
}

struct TrackerDisclosure: View {
    let title: String
    let detail: String
    var value: String = ""
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !value.isEmpty { Text(value).font(.title3.weight(.medium)).monospacedDigit() }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(TrackerStyle.ink)
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
    }
}

extension Color {
    static var trackerGroupedBackground: Color {
        TrackerStyle.background
    }

    static var trackerDarkGreen: Color {
        Color(red: 0.00, green: 0.42, blue: 0.22)
    }
}

struct DashboardCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(TrackerStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct PriorityChip: View {
    let value: Int?
    var colorValue: Int? = nil

    var body: some View {
        Text(value.map(String.init) ?? "-")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 28)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
            .accessibilityLabel("Adjusted priority \(value.map(String.init) ?? "none")")
    }

    private var color: Color {
        guard let value = colorValue ?? value else { return .secondary }
        if value > 20 { return .blue }
        if value >= 10 { return .trackerDarkGreen }
        if value >= 5 { return .green }
        if value >= 2 { return .yellow }
        if value == 1 { return .orange }
        return .red
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    @ViewBuilder
    func trackerInlineNavigationTitle() -> some View {
#if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}
