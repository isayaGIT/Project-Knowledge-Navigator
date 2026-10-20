import SwiftUI

/// Geometry helpers keep the visible frame window and its scroll position in the same coordinate system.
enum FilmstripMetrics {
    static func visibleCount(width: CGFloat, frameWidth: CGFloat, gap: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let step = frameWidth + gap
        guard width > 0, step > 0 else { return 1 }
        // Fit only whole frames. Using ceil would render a partial frame beyond the viewport edge.
        return min(itemCount, max(1, Int(floor((width + gap) / step))))
    }

    /// A scrollbar thumb can only travel across the range not already occupied by the viewport.
    static func scrollOffset(progress: CGFloat, itemCount: Int, visibleCount: Int) -> Int {
        let maxOffset = max(0, itemCount - max(1, visibleCount))
        let clampedProgress = min(max(progress, 0), 1)
        return Int((clampedProgress * CGFloat(maxOffset)).rounded())
    }

    /// Select the frame whose center is nearest to the pointer in the visible window.
    static func localIndex(x: CGFloat, frameWidth: CGFloat, gap: CGFloat, visibleCount: Int) -> Int {
        guard visibleCount > 1 else { return 0 }
        let step = frameWidth + gap
        guard step > 0 else { return 0 }
        let nearest = Int(((x - frameWidth / 2) / step).rounded())
        return min(max(nearest, 0), visibleCount - 1)
    }

    static func selectedIndex(x: CGFloat, width: CGFloat, itemCount: Int, visibleCount: Int,
                              frameWidth: CGFloat, gap: CGFloat) -> Int {
        guard itemCount > 0 else { return 0 }
        let progress = width > 0 ? min(max(x / width, 0), 1) : 0
        let start = scrollOffset(progress: progress, itemCount: itemCount, visibleCount: visibleCount)
        let local = localIndex(x: x, frameWidth: frameWidth, gap: gap, visibleCount: visibleCount)
        return min(max(start + local, 0), itemCount - 1)
    }
}

/// The filmstrip is both the viewport and its seek control. Click or drag directly on the frames.
struct FilmstripScrubber: View {
    let items: [NodeContent]
    var mediaURL: (NodeContent) -> URL = { URL(fileURLWithPath: $0.path) }
    @State private var scrollProgress: CGFloat = 0
    @State private var isScrubbing = false
    private let frameWidth: CGFloat = 54
    private let frameGap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let count = items.count
            let visibleCount = FilmstripMetrics.visibleCount(
                width: width, frameWidth: frameWidth, gap: frameGap, itemCount: count
            )
            let startIndex = FilmstripMetrics.scrollOffset(
                progress: scrollProgress, itemCount: count, visibleCount: visibleCount
            )
            let endIndex = min(count, startIndex + visibleCount)
            let pointerX = scrollProgress * width
            let current = FilmstripMetrics.selectedIndex(
                x: pointerX, width: width, itemCount: count, visibleCount: visibleCount,
                frameWidth: frameWidth, gap: frameGap
            )

            ZStack(alignment: .leading) {
                if count > 0 {
                    HStack(spacing: frameGap) {
                        ForEach(startIndex..<endIndex, id: \.self) { index in
                            thumbnail(for: items[index], index: index, selected: index == current)
                                .frame(width: frameWidth, height: geometry.size.height - 6)
                        }
                    }
                    .frame(height: geometry.size.height, alignment: .leading)
                }
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isScrubbing ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isScrubbing ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    isScrubbing = true
                    guard count > 0, width > 0 else { scrollProgress = 0; return }
                    // Progress controls the scroll offset; selection is the frame under the pointer.
                    // Keeping these separate prevents the moving window from changing the drag scale.
                    scrollProgress = min(max(value.location.x / width, 0), 1)
                }
                .onEnded { _ in isScrubbing = false })
            .accessibilityElement()
            .accessibilityLabel("Image filmstrip")
            .accessibilityValue("Image \(current + 1) of \(max(count, 1))")
            .help("Click or drag directly across the filmstrip to browse all images")
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
        .accessibilityLabel(item.title)
    }

}
