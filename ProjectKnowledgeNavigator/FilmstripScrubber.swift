import SwiftUI

/// A genuinely scrollable filmstrip: every image gets a frame, including images beyond the visible viewport.
/// Horizontal scrolling reveals the remaining frames; tapping a frame marks it as selected.
struct FilmstripScrubber: View {
    let items: [NodeContent]
    var mediaURL: (NodeContent) -> URL = { URL(fileURLWithPath: $0.path) }
    @State private var selectedIndex = 0
    private let frameWidth: CGFloat = 54
    private let frameGap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: frameGap) {
                    ForEach(items.indices, id: \.self) { index in
                        thumbnail(for: items[index], index: index, selected: index == selectedIndex)
                            .frame(width: frameWidth, height: max(1, geometry.size.height - 6))
                            .contentShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture { selectedIndex = index }
                            .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Image filmstrip")
            .help("Scroll horizontally to access every image; click a frame to select it")
        }
    }

    @ViewBuilder private func thumbnail(for item: NodeContent, index: Int, selected: Bool) -> some View {
        ZStack {
            if let image = NSImage(contentsOf: mediaURL(item)) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color(hue: Double((index * 37) % 360) / 360, saturation: 0.22, brightness: 0.84))
                Image(systemName: "photo").font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.45))
            }
            if selected { RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 2.5) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .bottomLeading) {
            Text("\(index + 1)").font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(.black.opacity(0.65)).padding(3)
        }
        .accessibilityLabel("\(index + 1): \(item.title)")
    }
}
