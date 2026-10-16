import SwiftUI

/// Semantic navigation symbols; the parent button supplies its accessible name.
enum MorningDockSymbol: Sendable, CaseIterable {
    case morning, play, pause, review, learn, settings
}

/// SF Symbols provide Apple's familiar navigation shapes and optical sizing.
struct MorningDockGlyph: View {
    let symbol: MorningDockSymbol

    var body: some View {
        Image(systemName: name)
            .font(.system(.title3, design: .default, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var name: String {
        switch symbol {
        case .morning: "house"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .review: "list.bullet"
        case .learn: "eye"
        case .settings: "gearshape"
        }
    }
}

/// The symbol itself is glass; its parent button supplies the larger touch target.
struct MorningFloatingGlassSymbol: View {
    let symbol: MorningDockSymbol
    let size: CGFloat
    var prefersOpaque = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = MorningGlassSymbolShape(symbol: symbol)
        Group {
            if reduceTransparency || prefersOpaque {
                shape.fill(.primary)
            } else if #available(iOS 26.0, macOS 26.0, *) {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(Color.primary.opacity(0.45)), in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct MorningGlassSymbolShape: Shape {
    let symbol: MorningDockSymbol

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        switch symbol {
        case .play:
            return roundedPath([
                CGPoint(x: box.minX + side * 0.10, y: box.minY + side * 0.04),
                CGPoint(x: box.maxX - side * 0.02, y: box.midY),
                CGPoint(x: box.minX + side * 0.10, y: box.maxY - side * 0.04)
            ], radius: side * 0.08)
        case .pause:
            var path = Path()
            for offset in [0.20, 0.58] {
                path.addRoundedRect(in: CGRect(x: box.minX + side * offset, y: box.minY + side * 0.06,
                                               width: side * 0.22, height: side * 0.88),
                                    cornerSize: CGSize(width: side * 0.05, height: side * 0.05))
            }
            return path
        case .settings:
            let points = (0..<32).map { index in
                let angle = CGFloat(index) * .pi / 16 - .pi / 2
                let radius = side * (index % 4 == 1 || index % 4 == 2 ? 0.50 : 0.40)
                return CGPoint(x: box.midX + cos(angle) * radius, y: box.midY + sin(angle) * radius)
            }
            let outline = roundedPath(points, radius: side * 0.025)
            let hole = Path(ellipseIn: box.insetBy(dx: side * 0.30, dy: side * 0.30))
            return outline.subtracting(hole)
        default:
            return Path()
        }
    }

    private func roundedPath(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in points.indices {
            path.addArc(tangent1End: points[index], tangent2End: points[(index + 1) % points.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

/// Let the native system compose the floating dock as one glass group.
struct MorningNavigationGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

/// A familiar call-site vocabulary rendered entirely as circles. Known system-name
/// strings select original dot patterns; there is no SF Symbol or stroke fallback.
/// Typical control size is 24–28 pt. The containing button still needs a 44 pt target.
struct MorningDottedIcon: View {
    let systemName: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // A plain SF Symbol now, as on Home: the dot-art glyphs are retired.
        Image(systemName: systemName)
            .resizable().scaledToFit()
            .fontWeight(contrast == .increased ? .semibold : .regular)
            .padding(2)
            .accessibilityHidden(true)
    }

    private var pattern: [String] {
        switch systemName {
        case "play", "play.fill":
            ["..x......", "..xx.....", "..xxx....", "..xxxx...", "..xxxxx..", "..xxxx...", "..xxx....", "..xx.....", "..x......"]
        case "pause", "pause.fill":
            [".........", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "........."]
        case "stop", "stop.fill":
            [".........", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", "........."]
        case "checkmark", "checkmark.circle", "checkmark.circle.fill":
            ["..xxxxx..", ".x.....x.", "x......xx", "x.....x.x", "x.x..x..x", "x..xx...x", "x.......x", ".x.....x.", "..xxxxx.."]
        case "sunrise", "sunrise.fill", "sun.horizon", "sun.horizon.fill", "sun.max", "sun.max.fill":
            ["....x....", ".x..x..x.", "..xxxxx..", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", "xxxxxxxxx", ".........", "..xxxxx.."]
        case "record.circle", "record.circle.fill":
            ["..xxxxx..", ".x.....x.", "x.......x", "x..xxx..x", "x..xxx..x", "x..xxx..x", "x.......x", ".x.....x.", "..xxxxx.."]
        case "eye", "eye.fill", "viewfinder":
            [".........", "...xxx...", "..x...x..", ".x..x..x.", "x..xxx..x", ".x..x..x.", "..x...x..", "...xxx...", "........."]
        case "calendar":
            ["..x...x..", ".xxxxxxx.", ".xx...xx.", ".xxxxxxx.", ".x.....x.", ".x.x.x.x.", ".x.....x.", ".x.x.x.x.", ".xxxxxxx."]
        case "list.bullet", "list.bullet.clipboard":
            [".........", ".x..xxxx.", ".........", ".........", ".x..xxxx.", ".........", ".........", ".x..xxxx.", "........."]
        case "arrow.clockwise", "clock.arrow.circlepath":
            ["..xxxxx..", ".x.....x.", "x......xx", "x.....xxx", "x........", "x........", "x.......x", ".x.....x.", "..xxxxx.."]
        case "info.circle", "info.circle.fill", "exclamationmark.circle":
            ["..xxxxx..", ".x.....x.", "x...x...x", "x.......x", "x..xx...x", "x...x...x", "x..xxx..x", ".x.....x.", "..xxxxx.."]
        case "newspaper", "newspaper.fill", "doc.text":
            [".xxxxxxx.", ".x.....x.", ".x.xxx.x.", ".x.....x.", ".x.x.x.x.", ".x.x.x.x.", ".x.....x.", ".x.xxx.x.", ".xxxxxxx."]
        case "globe", "network":
            ["..xxxxx..", ".x.x.x.x.", "x..x.x..x", "x..x.x..x", "xxxxxxxxx", "x..x.x..x", "x..x.x..x", ".x.x.x.x.", "..xxxxx.."]
        case "clock", "clock.fill":
            ["..xxxxx..", ".x.....x.", "x...x...x", "x...x...x", "x...xxx.x", "x.......x", "x.......x", ".x.....x.", "..xxxxx.."]
        case "alarm", "alarm.fill":
            [".xx...xx.", "x..xxx..x", "..x...x..", ".x..x..x.", ".x..xxx..", ".x.....x.", "..x...x..", "...xxx...", "..x...x.."]
        case "timer", "stopwatch", "stopwatch.fill":
            ["...xxx...", "....x..x.", "..xxxxx..", ".x.....x.", "x...x...x", "x...x...x", "x...xxx.x", ".x.....x.", "..xxxxx.."]
        case "slider.horizontal.3", "gearshape", "gearshape.fill":
            [".........", ".....x...", ".xxxx.xxx", ".....x...", "..x......", ".x.xxxxx.", "..x......", ".....x...", ".xxxx.xxx"]
        case "arrow.right", "chevron.right", "forward.end", "forward.end.fill":
            [".........", "....x....", ".....x...", "......x..", ".xxxxxxx.", "......x..", ".....x...", "....x....", "........."]
        case "arrow.left", "chevron.left":
            [".........", "....x....", "...x.....", "..x......", ".xxxxxxx.", "..x......", "...x.....", "....x....", "........."]
        case "plus", "plus.circle", "plus.circle.fill":
            [".........", "....x....", "....x....", "....x....", ".xxxxxxx.", "....x....", "....x....", "....x....", "........."]
        case "circle.fill":
            [".........", "...xxx...", "..xxxxx..", ".xxxxxxx.", ".xxxxxxx.", ".xxxxxxx.", "..xxxxx..", "...xxx...", "........."]
        case "circle":
            [".........", "...xxx...", "..x...x..", ".x.....x.", ".x.....x.", ".x.....x.", "..x...x..", "...xxx...", "........."]
        case "xmark", "xmark.circle", "xmark.circle.fill":
            [".........", ".x.....x.", "..x...x..", "...x.x...", "....x....", "...x.x...", "..x...x..", ".x.....x.", "........."]
        case "ellipsis", "ellipsis.circle":
            [".........", ".........", ".........", ".........", ".x..x..x.", ".........", ".........", ".........", "........."]
        case "mic", "mic.fill", "waveform":
            ["...xxx...", "...x.x...", "...x.x...", "...x.x...", ".x.xxx.x.", ".x.....x.", "..xxxxx..", "....x....", "..xxxxx.."]
        case "speaker.wave.2", "speaker.wave.2.fill":
            [".........", "....x..x.", "...xx...x", ".xxxx.x.x", ".xxxx.x.x", ".xxxx.x.x", "...xx...x", "....x..x.", "........."]
        case "bubble.left.and.bubble.right.fill", "message", "message.fill", "bubble.left":
            [".xxxxxx..", "x......x.", "x......x.", "x......x.", "x......x.", ".xxx.xxx.", "...x.x...", "...xx....", "........."]
        case "envelope", "envelope.fill", "envelope.badge", "mail":
            [".........", ".xxxxxxx.", ".xx...xx.", ".x.x.x.x.", ".x..x..x.", ".x.....x.", ".x.....x.", ".xxxxxxx.", "........."]
        case "leaf", "leaf.fill", "heart", "heart.fill":
            [".........", "..xx.xx..", ".x..x..x.", ".x.....x.", "..x...x..", "...x.x...", "....x....", ".........", "........."]
        case "moon", "moon.fill", "moon.stars", "moon.stars.fill":
            ["...xxxx..", "..xx.....", ".xx......", ".xx......", ".xx......", ".xxx.....", "..xxxx.xx", "...xxxxx.", "........."]
        case "arrow.up", "arrow.up.circle":
            ["....x....", "...xxx...", "..x.x.x..", ".x..x..x.", "....x....", "....x....", "....x....", "....x....", "........."]
        case "lock.shield", "lock.shield.fill", "lock", "lock.fill":
            ["...xxx...", "..x...x..", "..x...x..", ".xxxxxxx.", ".x.....x.", ".x..x..x.", ".x..x..x.", ".x.....x.", ".xxxxxxx."]
        case "platter.filled.top.iphone", "iphone", "iphone.gen3":
            ["..xxxxx..", "..x...x..", "..xxxxx..", "..x...x..", "..x...x..", "..x...x..", "..x...x..", "..x.x.x..", "..xxxxx.."]
        case "rectangle.on.rectangle", "rectangle.on.rectangle.angled":
            ["..xxxxxx.", "..x....x.", "xxxxxxxx.", "x.....xx.", "x.....xx.", "x.....xx.", "x.....xx.", "x.....x..", "xxxxxxx.."]
        case "chevron.down":
            [".........", ".........", ".x.....x.", "..x...x..", "...x.x...", "....x....", ".........", ".........", "........."]
        case "chevron.up":
            [".........", ".........", "....x....", "...x.x...", "..x...x..", ".x.....x.", ".........", ".........", "........."]
        case "arrow.down", "arrow.down.circle":
            [".........", "....x....", "....x....", "....x....", "....x....", ".x..x..x.", "..x.x.x..", "...xxx...", "....x...."]
        case "square.and.pencil", "pencil", "pencil.and.outline":
            [".......x.", "......xxx", ".....xxx.", "....xxx..", "...xxx...", "..xxx....", ".xxx.....", ".xx......", "........."]
        default:
            // A distinct cluster is preferable to quietly reintroducing a stroke icon.
            ["....x....", "....x....", "..x.x.x..", "...xxx...", "xxxxxxxxx", "...xxx...", "..x.x.x..", "....x....", "....x...."]
        }
    }
}

private struct MorningDottedIconShape: Shape {
    let pattern: [String]
    let strong: Bool

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let cell = side / 10
        let radius = cell * (strong ? 0.40 : 0.34)
        var path = Path()
        for (row, line) in pattern.enumerated() {
            for (column, value) in line.enumerated() where value == "x" {
                let x = rect.midX + (CGFloat(column) - 4) * cell
                let y = rect.midY + (CGFloat(row) - 4) * cell
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}
