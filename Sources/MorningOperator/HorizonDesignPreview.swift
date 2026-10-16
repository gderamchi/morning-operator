#if DEBUG
import SwiftUI

/// Proof of the "Horizon" design direction (design/gallery): one line divides
/// sky from ground, what is still to come lives in the sky, what is done has
/// sunk into the grass, and a pixel sun climbs as the morning advances.
/// Reached only with `--design-preview`; it never touches the current look.
/// Fonts are system stand-ins for Fraunces and IBM Plex Mono.
struct HorizonDesignPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = 4

    private static let moments: [(String, Int)] = [
        ("Your day", 3), ("People and messages", 8), ("Mail", 7), ("Make some tea", 5),
        ("A little reading", 6), ("A moment to move", 10), ("One thought for later", 3)
    ]
    @State private var completed = 0

    private var grass: Color { Color(red: 0.027, green: 0.145, blue: 0.047) }
    private var bone: Color { Color(red: 0.949, green: 0.929, blue: 0.890) }
    private var night: Color { Color(red: 0.043, green: 0.078, blue: 0.125) }
    private var clay: Color { Color(red: 0.769, green: 0.396, blue: 0.247) }
    private var clayLift: Color { Color(red: 0.847, green: 0.463, blue: 0.302) }
    private var sky: Color { colorScheme == .dark ? night : bone }
    private var ink: Color { colorScheme == .dark ? bone : Color(red: 0.078, green: 0.129, blue: 0.102) }
    private var total: Int { Self.moments.reduce(0) { $0 + $1.1 } }
    private var done: Int { Self.moments.prefix(completed).reduce(0) { $0 + $1.1 } }

    var body: some View {
        GeometryReader { geo in
            let groundMin = geo.size.height * 0.2
            let groundMax = geo.size.height * 0.7
            let ground = groundMin + (groundMax - groundMin) * CGFloat(done) / CGFloat(max(total, 1))
            ZStack(alignment: .bottom) {
                sky.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("good ").font(.system(size: 46, weight: .light, design: .serif))
                            + Text("morning").font(.system(size: 46, weight: .light, design: .serif).italic()).foregroundStyle(clay)
                        Spacer()
                        Text("\(total - done) min").font(.system(.caption, design: .monospaced)).foregroundStyle(ink.opacity(0.6))
                    }
                    .padding(.top, 8)
                    Spacer(minLength: 8)
                    momentList(Self.moments.dropFirst(completed), tint: ink)
                }
                .padding(.horizontal, 28)
                .frame(height: geo.size.height - ground, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .foregroundStyle(ink)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(completed) of \(Self.moments.count) moments done, \(total - done) minutes left")

                groundView(height: ground)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: completed)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func momentList(_ items: ArraySlice<(String, Int)>, tint: Color) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.0).font(.system(size: 17, weight: .light, design: .monospaced))
                    Spacer()
                    Text("\(item.1) MIN").font(.system(size: 11, design: .monospaced)).kerning(1).opacity(0.6)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) { if index > 0 { Rectangle().fill(tint.opacity(0.14)).frame(height: 1) } }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.0), \(item.1) minutes")
            }
        }
        .foregroundStyle(tint)
    }

    private func groundView(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            grass
            VStack(alignment: .leading, spacing: 0) {
                momentList(Self.moments.prefix(completed), tint: bone.opacity(0.62))
                Spacer(minLength: 0)
                HStack {
                    Button("Learn") {}.foregroundStyle(bone.opacity(0.62))
                    Spacer()
                    Button("History") {}.foregroundStyle(bone.opacity(0.62))
                    Spacer()
                    Button(completed < Self.moments.count ? "Next" : "Again") {
                        completed = completed < Self.moments.count ? completed + 1 : 0
                    }
                    .padding(.horizontal, 22).padding(.vertical, 15)
                    .background(clayLift, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(grass).fontWeight(.medium)
                }
                .font(.system(size: 11, design: .monospaced)).textCase(.uppercase).kerning(2)
                .padding(.bottom, 34)
            }
            .padding(.horizontal, 28).padding(.top, 14)
        }
        .frame(height: height)
        .overlay(alignment: .top) { horizon }
        .accessibilityElement(children: .contain)
    }

    /// The join: a dithered pixel edge (never a hard line) with the sun breaking it.
    private var horizon: some View {
        ZStack(alignment: .bottom) {
            ditherEdge.frame(height: cell * 6).offset(y: -cell * 3)
            pixelSun.offset(y: -cell * CGFloat(2 + completed * 2))
        }
        .accessibilityHidden(true) // decorative; progress is spoken by the lists and the heading
    }

    private var ditherEdge: some View {
        Canvas { context, size in
            let bayer: [[Int]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
            let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell)
            for y in 0..<rows { for x in 0..<cols {
                let t = Double(y) / Double(max(rows - 1, 1))
                let th = (Double(bayer[y % 4][x % 4]) + 0.5) / 16
                let color = t > th ? grass : sky
                context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(color))
            } }
        }
    }

    private var pixelSun: some View {
        Canvas { context, size in
            let n = 18
            for y in 0..<n { for x in 0..<n {
                let d = hypot(Double(x) + 0.5 - 9, Double(y) + 0.5 - 9)
                if d <= 8.5 {
                    let rim = d > 7.6 && (x + y) % 2 == 0
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)),
                                 with: .color(rim ? Color(red: 0.910, green: 0.537, blue: 0.365) : clayLift))
                }
            } }
        }
        .frame(width: cell * 18, height: cell * 18)
        .mask(alignment: .top) { Rectangle().frame(height: cell * 9) } // only the half above the line shows
    }
}

#Preview("Horizon — light") { HorizonDesignPreview() }
#Preview("Horizon — early morning") { HorizonDesignPreview().preferredColorScheme(.dark) }
#endif
