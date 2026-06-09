import SwiftUI

/// A ScrollView that hugs its content's natural height up to a cap.
///
/// A plain `ScrollView` is fully flexible: inside the adaptive-height panel it
/// collapses to whatever space is proposed, so the panel's reported content
/// height never grows (chicken-and-egg). This wrapper measures the inner
/// content and gives the ScrollView an explicit height, which the panel's
/// height reporting can then account for.
private struct InnerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SelfSizingScrollView<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: InnerHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .onPreferenceChange(InnerHeightKey.self) { contentHeight = $0 }
        .frame(height: max(1, min(contentHeight, maxHeight)))
    }
}
