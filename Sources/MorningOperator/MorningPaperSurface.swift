import SwiftUI

/// Utility pages use a plain native background; explicit artwork previews retain paper.
struct MorningPaperSurface: View {
    /// Pass a theme only for a component preview; nil uses the adaptive utility palette.
    var theme: MorningTheme? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            theme?.paper ?? MorningStyle.background
            if theme != nil && !reduceTransparency && contrast != .increased {
                MorningPaperGrain()
            }
        }
        .ignoresSafeArea()
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A cached, irregular field of sub-point flecks, rather than a regular dot screen.
/// The largest fleck is 0.56 pt wide. Neutral warm ink at 3.5% opacity keeps the
/// cream dominant and avoids the blue/purple cast of a full-page ink halftone.
private struct MorningPaperGrain: View {
    private static let side: CGFloat = 160
    private static let tile: Path = {
        var path = Path()
        var seed: UInt64 = 0x4D4F_5245_5041_5045
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 40) / CGFloat(1 << 24)
        }
        for _ in 0..<1_800 {
            let x = 0.3 + next() * (side - 0.6)
            let y = 0.3 + next() * (side - 0.6)
            let radius = 0.14 + next() * 0.14
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                      width: radius * 2, height: radius * 2))
        }
        return path
    }()

    var body: some View {
        Canvas { context, size in
            let ink = Color(red: 0.24, green: 0.20, blue: 0.15).opacity(0.035)
            for y in stride(from: CGFloat.zero, to: size.height, by: Self.side) {
                for x in stride(from: CGFloat.zero, to: size.width, by: Self.side) {
                    var tileContext = context
                    tileContext.translateBy(x: x, y: y)
                    tileContext.fill(Self.tile, with: .color(ink))
                }
            }
        }
    }
}
