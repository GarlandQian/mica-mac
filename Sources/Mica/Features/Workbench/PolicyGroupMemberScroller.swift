import SwiftUI

struct PolicyGroupMemberScroller<Content: View>: View {
    let maximumHeight: CGFloat
    let initialHeight: CGFloat
    let accessibilityLabel: String
    @Binding var scrollPosition: ScrollPosition
    private let content: Content

    @State private var measuredContentHeight: CGFloat?

    init(
        maximumHeight: CGFloat,
        initialHeight: CGFloat,
        accessibilityLabel: String,
        scrollPosition: Binding<ScrollPosition>,
        @ViewBuilder content: () -> Content
    ) {
        self.maximumHeight = maximumHeight
        self.initialHeight = initialHeight
        self.accessibilityLabel = accessibilityLabel
        _scrollPosition = scrollPosition
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PolicyGroupMemberContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .scrollIndicators(.visible)
        .scrollPosition($scrollPosition)
        .frame(height: resolvedHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MicaStyle.contentFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onPreferenceChange(PolicyGroupMemberContentHeightKey.self) { height in
            guard height > 0 else { return }
            measuredContentHeight = height
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var resolvedHeight: CGFloat {
        min(maximumHeight, measuredContentHeight ?? initialHeight)
    }
}

private struct PolicyGroupMemberContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
