import SwiftUI

/// Geometry helpers keep the filmstrip's pixel scroll, rendered window, and selection on one scale.
enum FilmstripMetrics {
    static func contentWidth(itemCount: Int, frameWidth: CGFloat, gap: CGFloat) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        return CGFloat(itemCount) * frameWidth + CGFloat(max(0, itemCount - 1)) * gap
    }

    static func maxScrollOffset(width: CGFloat, itemCount: Int, frameWidth: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, contentWidth(itemCount: itemCount, frameWidth: frameWidth, gap: gap) - max(0, width))
    }

    static func scrollOffset(progress: CGFloat, width: CGFloat, itemCount: Int,
                             frameWidth: CGFloat, gap: CGFloat) -> CGFloat {
        let maxOffset = maxScrollOffset(width: width, itemCount: itemCount, frameWidth: frameWidth, gap: gap)
        return min(max(progress, 0), 1) * maxOffset
    }

    static func firstVisibleIndex(scrollOffset: CGFloat, frameWidth: CGFloat, gap: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0, frameWidth + gap > 0 else { return 0 }
        return min(max(Int(floor(max(0, scrollOffset) / (frameWidth + gap))), 0), itemCount - 1)
    }

    /// The sub-frame offset makes the filmstrip move continuously instead of jumping one frame at a time.
    static func partialFrameOffset(scrollOffset: CGFloat, frameWidth: CGFloat, gap: CGFloat) -> CGFloat {
        let step = frameWidth + gap
        guard step > 0 else { return 0 }
        let offset = max(0, scrollOffset)
        return offset - floor(offset / step) * step
    }

    static func visibleCount(width: CGFloat, frameWidth: CGFloat, gap: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let step = frameWidth + gap
        guard width > 0, step > 0 else { return 1 }
        return min(itemCount, max(1, Int(floor((width + gap) / step))))
    }

    /// Select the frame whose center is nearest to the pointer's content-space coordinate.
    static func selectedIndex(contentX: CGFloat, itemCount: Int, frameWidth: CGFloat, gap: CGFloat) -> Int {
        guard itemCount > 0, frameWidth + gap > 0 else { return 0 }
        let nearest = Int(((contentX - frameWidth / 2) / (frameWidth + gap)).rounded())
        return min(max(nearest, 0), itemCount - 1)
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
            let totalWidth = FilmstripMetrics.contentWidth(itemCount: count, frameWidth: frameWidth, gap: frameGap)
            let scrollOffset = FilmstripMetrics.scrollOffset(
                progress: scrollProgress, width: width, itemCount: count,
                frameWidth: frameWidth, gap: frameGap
            )
            let startIndex = FilmstripMetrics.firstVisibleIndex(
                scrollOffset: scrollOffset, frameWidth: frameWidth, gap: frameGap, itemCount: count
            )
            let visibleCount = FilmstripMetrics.visibleCount(
                width: width, frameWidth: frameWidth, gap: frameGap, itemCount: count
            )
            // Include extra frames for the fractional scroll at either edge; the viewport clips them.
            let renderEndIndex = min(count, startIndex + visibleCount + 2)
            let pointerX = scrollProgress * width
            let current = FilmstripMetrics.selectedIndex(
                contentX: pointerX + scrollOffset, itemCount: count,
                frameWidth: frameWidth, gap: frameGap
            )

            HStack(spacing: frameGap) {
                if count > 0 {
                    ForEach(startIndex..<renderEndIndex, id: \.self) { index in
                        thumbnail(for: items[index], index: index, selected: index == current)
                            .frame(width: frameWidth, height: geometry.size.height - 6)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: -FilmstripMetrics.partialFrameOffset(scrollOffset: scrollOffset, frameWidth: frameWidth, gap: frameGap))
            .frame(width: width, height: geometry.size.height, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            // Draw the viewport border after clipping its contents so the border itself is never cut off.
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isScrubbing ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isScrubbing ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    isScrubbing = true
                    guard count > 0, width > 0, totalWidth > width else {
                        scrollProgress = 0
                        return
                    }
                    // Like a scrollbar, the pointer position maps to the whole scroll range.
                    // Content then follows it in pixel space, without quantizing motion to frame steps.
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
