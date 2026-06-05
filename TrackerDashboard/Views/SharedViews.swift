import SwiftUI

extension Color {
    static var trackerGroupedBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.systemGroupedBackground)
#endif
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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        if value >= 8 { return .red }
        if value >= 5 { return .orange }
        if value >= 2 { return .blue }
        return .green
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
