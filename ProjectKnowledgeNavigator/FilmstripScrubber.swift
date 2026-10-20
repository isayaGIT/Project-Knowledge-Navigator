import SwiftUI

/// The filmstrip is the seek control. Click or drag directly on the frames to scrub the full collection.
struct FilmstripScrubber: View {
    let items: [NodeContent]
    var mediaURL: (NodeContent) -> URL = { URL(fileURLWithPath: $0.path) }
    @State private var selectedIndex = 0
    @State private var isScrubbing = false
    private let frameWidth: CGFloat = 54
    private let frameGap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let count = items.count
            let current = min(max(selectedIndex, 0), max(0, count - 1))
            // Fit every frame into the available width. Keep the original direct
            // click-and-drag scrubbing gesture, but never truncate the collection.
            let fittedFrameWidth = count > 0
                ? min(frameWidth, max(24, (width - CGFloat(max(0, count - 1)) * frameGap) / CGFloat(count)))
                : frameWidth
            ZStack(alignment: .leading) {
                if count > 0 {
                    HStack(spacing: frameGap) {
                        ForEach(items.indices, id: \.self) { index in
                            thumbnail(for: items[index], index: index, selected: index == current)
                                .frame(width: fittedFrameWidth, height: geometry.size.height - 6)
                        }
                    }
                    .frame(height: geometry.size.height, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }
                RoundedRectangle(cornerRadius: 6).stroke(isScrubbing ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isScrubbing ? 2 : 1).allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    isScrubbing = true
                    guard count > 1, width > 0 else { selectedIndex = 0; return }
                    let normalized = min(max(value.location.x / width, 0), 1)
                    selectedIndex = Int((normalized * CGFloat(count - 1)).rounded())
                }
                .onEnded { _ in isScrubbing = false })
            .accessibilityElement().accessibilityLabel("Image filmstrip")
            .accessibilityValue("Image \(current + 1) of \(max(count, 1))")
            .help("Click or drag directly across the filmstrip to scrub through all images")
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
