import SwiftUI
import MorningCore

/// Every element of this mark is a separate circle. No stroked path, symbol font,
/// raster texture or runtime image download is used.
struct MorningDottedSunrise: Shape {
    enum Part { case sun, rays, all }
    var part: Part = .all

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        if part != .rays {
            for row in 0...7 {
                let y = CGFloat(15 + row * 4)
                for column in 0...13 {
                    let x = CGFloat(30 + column * 4)
                    let distance = hypot(x - 56, y - 44) / 25
                    if distance <= 1 {
                        dot(x, y, 1.15 + 0.7 * (1 - distance * distance))
                    }
                }
            }
        }
        if part != .sun {
            // Separated round impressions suggest rays and the horizon.
            for degree in [25.0, 55, 90, 125, 155] {
                let angle = degree * .pi / 180
                for reach in [32.0, 37.0] {
                    dot(56 + cos(angle) * reach, 44 - sin(angle) * reach, 1.6)
                }
            }
            for column in 0...14 { dot(CGFloat(21 + column * 5), 49, 1.6) }
            for column in 0...7 { dot(CGFloat(38 + column * 5), 56, 1.1) }
        }
        let scale = min(rect.width / 112, rect.height / 68)
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 56 * scale, ty: rect.midY - 34 * scale))
    }
}

/// A printed solar disc or crescent. A regular dot field gives the silhouette a
/// soft edge while each actual impression remains crisp and opaque.
struct MorningDottedDisc: Shape {
    enum Kind { case sun, moon }
    var kind: Kind = .sun

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let cells = 23
        let cell = side / CGFloat(cells)
        var path = Path()
        for row in 0..<cells {
            for column in 0..<cells {
                let x = (CGFloat(column) + 0.5) / CGFloat(cells)
                let y = (CGFloat(row) + 0.5) / CGFloat(cells)
                let distance = hypot(x - 0.5, y - 0.5) / 0.49
                guard distance < 1 else { continue }
                if kind == .moon, hypot(x - 0.68, y - 0.34) < 0.46 { continue }
                let radius = cell * (0.18 + 0.27 * (1 - distance * distance))
                let center = CGPoint(x: origin.x + x * side, y: origin.y + y * side)
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}

/// The scene is driven by local time, independently of routine completion.
/// It is decorative: cards and controls remain opaque reading surfaces above it.
struct MorningCelestialArtwork: View {
    let scene: MorningCelestialScene
    /// When the person last touched the sun: its lines ripple, then settle.
    var kick: Date? = nil
    var kicks: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.72, 300)
            ZStack {
                let sunX = geometry.size.width * scene.sun.centerX
                let sunY = geometry.size.height * scene.sun.centerY
                // The sun's darker lower half spreads into the page: densest and darkest
                // against the disc, thinning out to the sides and down.
                // The page colour follows the same fade: deepest rust against the sun's
                // lower half, lightening outwards, wider than tall and further down than up.
                // The sun's own cloud bands carry on across the sky at its height.
                MorningCloudBands(sun: CGPoint(x: sunX, y: sunY), diameter: diameter, kick: kick, kicks: kicks)
                    .opacity(scene.sun.opacity)
                MorningSolarArtwork(opacity: scene.sun.opacity)
                    .frame(width: diameter, height: diameter)

                    // A feathered rim rather than a hard outline.
                    .mask(RadialGradient(stops: [.init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                         center: .center, startRadius: 0, endRadius: diameter / 2))
                    .position(x: sunX, y: sunY)

                let moonX = geometry.size.width * scene.moon.centerX
                let moonY = geometry.size.height * scene.moon.centerY
                let moonDiameter = diameter * 0.82
                // Stars above the horizon, faint and fixed.
                MorningStarField(horizon: moonY + moonDiameter * 0.9)
                    .opacity(scene.moon.opacity)
                MorningLunarArtwork()
                    .frame(width: moonDiameter, height: moonDiameter)

                    .opacity(scene.moon.opacity)
                    .position(x: moonX, y: moonY)

            }
            .animation(reduceMotion ? nil : .linear(duration: 60), value: scene)
        }
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A small, fixed sequence of pseudo-random numbers, so the artwork is the same on
/// every launch and every device.
struct MorningSeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return CGFloat(z % 1_000_000) / 1_000_000
    }
    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * next() }
}

/// Long, soft streaks in the sun's own band colours: cream near its top, orange through
/// its middle, rust at its lower edge. They run past the disc so its clouds continue
/// into the sky instead of stopping at the rim.
struct MorningCloudBands: View {
    var sun: CGPoint
    var diameter: CGFloat
    var kick: Date? = nil
    /// How many times the sun was touched: each touch slides the whole sky one step right.
    var kicks: Int = 0

    var body: some View {
        let settling = kick.map { Date().timeIntervalSince($0) < 1.6 } ?? false
        TimelineView(.animation(paused: !settling)) { timeline in
            let t = kick.map { timeline.date.timeIntervalSince($0) } ?? 99
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                var random = MorningSeededRandom(seed: 7)
                context.addFilter(.blur(radius: 2.6))
                // Each touch glides the sky one step to the right, easing to a stop; nearer
                // (lower) lines travel a little further, as if the whole page drifted.
                let progress = 1 - pow(1 - min(1, t / 1.4), 3)
                let shift = 90 * (CGFloat(max(0, kicks - 1)) + (kicks > 0 ? progress : 0))
                for index in 0..<64 {
                    // Spread from the top of the screen to the bottom; colour follows the
                    // sun's bands: pale above it, orange at its middle, rust at and below its edge.
                    let y0 = random.range(-0.02, 1.02) * size.height
                    let band = (y0 - (sun.y - diameter / 2)) / diameter
                    let length = size.width * random.range(0.35, 0.95)
                    let start = random.range(-0.2, 1.0) * (size.width - length * 0.6)
                    let thickness = random.range(2.0, 6.5)
                    // Fainter towards the very top of the screen.
                    let alpha = random.range(0.35, 0.7) * (0.35 + 0.65 * min(1, max(0, y0 / (size.height * 0.35))))
                    let speed = 0.6 + 0.8 * min(1, max(0, y0 / size.height)) + random.range(-0.1, 0.1)
                    let span = size.width + length
                    var x = (start + length + shift * speed).truncatingRemainder(dividingBy: span)
                    if x < 0 { x += span }
                    x -= length
                    let y = y0
                    let colour: Color
                    if band < 0.3 { colour = Color(red: 0.97, green: 0.78, blue: 0.66) }
                    else if band < 0.65 { colour = Color(red: 0.95, green: 0.60, blue: 0.40) }
                    else { colour = Color(red: 0.82, green: 0.38, blue: 0.26) }
                    let rect = CGRect(x: x, y: y, width: length, height: thickness)
                    context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2),
                                 with: .linearGradient(Gradient(stops: [.init(color: colour.opacity(0), location: 0),
                                                                        .init(color: colour.opacity(alpha), location: 0.3),
                                                                        .init(color: colour.opacity(alpha), location: 0.7),
                                                                        .init(color: colour.opacity(0), location: 1)]),
                                                   startPoint: CGPoint(x: rect.minX, y: y), endPoint: CGPoint(x: rect.maxX, y: y)))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The sun's reflection on water: rows of short bright glints under the disc. Rows get
/// further apart and wider, glints thinner and fainter, the lower they are, as a sea
/// seen in perspective. With motion allowed, each glint breathes on its own slow beat.
struct MorningWaterGlints: View {
    var sun: CGPoint
    var diameter: CGFloat
    var glint: Color
    var animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animated)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                var random = MorningSeededRandom(seed: 21)
                let top = sun.y + diameter * 0.42
                // The path of light: a soft golden column, narrow at the sun, wider below.
                var pillar = context
                pillar.addFilter(.blur(radius: 18))
                var column = Path()
                column.move(to: CGPoint(x: sun.x - diameter * 0.22, y: top))
                column.addLine(to: CGPoint(x: sun.x + diameter * 0.22, y: top))
                column.addLine(to: CGPoint(x: sun.x + diameter * 0.55, y: size.height + 20))
                column.addLine(to: CGPoint(x: sun.x - diameter * 0.55, y: size.height + 20))
                column.closeSubpath()
                pillar.fill(column, with: .linearGradient(Gradient(colors: [glint.opacity(0.55), glint.opacity(0.18), glint.opacity(0.05)]),
                                                           startPoint: CGPoint(x: sun.x, y: top),
                                                           endPoint: CGPoint(x: sun.x, y: size.height)))
                context.addFilter(.blur(radius: 0.9))
                var y = top
                var row = 0
                while y < size.height + 10 {
                    let depth = min(1, max(0, (y - top) / max(1, size.height - top)))
                    let spread = diameter * (0.30 + 0.75 * depth)
                    let count = 3 + Int(random.range(0, 4))
                    for index in 0..<count {
                        // Gathered towards the middle of the path, a few strays outside it.
                        let offset = (random.next() + random.next() + random.next()) / 1.5 - 1
                        let x = sun.x + offset * spread
                        let length = random.range(14, 58) * (1 - 0.25 * depth)
                        let thickness = 1.6 + 2.2 * depth
                        let phase = Double(random.next()) * 6.28 + Double(row) * 0.7 + Double(index)
                        let shimmer = 0.55 + 0.45 * sin(time * 1.4 + phase)
                        let alpha = (0.85 - 0.6 * depth) * (1 - 0.7 * abs(offset)) * shimmer
                        let drift = animated ? CGFloat(sin(time * 0.6 + phase)) * 3 : 0
                        let rect = CGRect(x: x - length / 2 + drift, y: y, width: length, height: thickness)
                        context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2), with: .color(glint.opacity(alpha)))
                    }
                    y += 4 + 12 * depth
                    row += 1
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A few hundred faint stars, fixed in place and thinning towards the horizon.
struct MorningStarField: View {
    var horizon: CGFloat
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var random = MorningSeededRandom(seed: 3)
            let bottom = min(size.height, horizon)
            for _ in 0..<220 {
                let x = random.next() * size.width, y = random.next() * bottom
                let height = 1 - y / max(1, bottom)
                let r = random.range(0.4, 1.3)
                let alpha = random.range(0.25, 0.9) * (0.3 + 0.7 * height)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A radial fade with many stops on an eased curve, so the colour thins out without
/// the visible rings a two- or three-stop gradient draws on a phone screen.
enum MorningSmoothGlow {
    static func gradient(color: Color, strength: Double, radius: CGFloat) -> RadialGradient {
        let steps = 24
        let stops: [Gradient.Stop] = (0...steps).map { index in
            let t = Double(index) / Double(steps)
            // Smootherstep fall-off: flat at the centre, flat as it reaches the page.
            let eased = 1 - (t * t * t * (t * (t * 6 - 15) + 10))
            return .init(color: color.opacity(strength * eased), location: t)
        }
        return RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: radius)
    }
}

/// A fixed, very fine grain over the page. It breaks up the colour steps a smooth
/// gradient would otherwise show, and reads as paper rather than as a pattern.
struct MorningGrain: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var light = Path(), dark = Path()
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return CGFloat(seed % 10_000) / 10_000
            }
            let count = Int(size.width * size.height / 9)
            for index in 0..<count {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                if index % 2 == 0 { light.addRect(rect) } else { dark.addRect(rect) }
            }
            context.fill(light, with: .color(.white.opacity(0.10)))
            context.fill(dark, with: .color(.black.opacity(0.06)))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A soft shadow made of dots around a point: near it the dots are large and close to
/// full strength, and they shrink and fade the further they are, so a body melts into
/// the page. Drawn once per size in one Canvas, grouped into a few strength levels.
struct MorningRadiantDots: View {
    var anchor: CGPoint
    var reach: CGFloat
    var color: Color

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let cell: CGFloat = 3.6
            let levels = 6
            var paths = Array(repeating: Path(), count: levels)
            var y: CGFloat = cell / 2
            var row = 0
            while y < size.height + cell {
                var x: CGFloat = row % 2 == 0 ? cell / 2 : cell
                while x < size.width + cell {
                    let dx = x - anchor.x
                    // Spread wider than tall, and further downwards than upwards.
                    let dy = (y - anchor.y) * (y < anchor.y ? 3.0 : 0.85)
                    let distance = (dx * dx + dy * dy).squareRoot() / reach
                    // Close to the body, and also everywhere lower on the page: the dots
                    // cover the whole screen, finest at the top and fullest at the bottom.
                    let strength = exp(-distance * distance * 1.3)
                    if strength > 0.02 {
                        let radius = 0.3 + 1.15 * strength
                        let level = min(levels - 1, Int(strength * CGFloat(levels)))
                        paths[level].addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    }
                    x += cell
                }
                y += cell * 0.866
                row += 1
            }
            for level in 0..<levels {
                context.fill(paths[level], with: .color(color.opacity(0.06 + 0.62 * Double(level + 1) / Double(levels))))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Fine dots in a body's colours, densest under its rim and fading outwards.
struct MorningDotHalo: View {
    var colors: [Color]
    var diameter: CGFloat
    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .mask(MorningHalftone(color: .black, opacity: 1, cell: 4.5, radius: 1.05))
            .mask(RadialGradient(stops: [.init(color: .clear, location: 0.38),
                                         .init(color: .black, location: 0.50),
                                         .init(color: .clear, location: 1)],
                                 center: .center, startRadius: 0, endRadius: diameter * 0.95))
            .frame(width: diameter * 1.9, height: diameter * 1.9)
    }
}

/// A column of fine dots falling from a body to the bottom of the page, strongest in
/// the middle and fading to the sides and towards the bottom.
struct MorningDotTrail: View {
    var colors: [Color]
    var width: CGFloat
    var height: CGFloat
    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .mask(MorningHalftone(color: .black, opacity: 1, cell: 4.5, radius: 1.05))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.75), location: 0.5),
                                         .init(color: .black.opacity(0.35), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.5),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: height)
    }
}

/// The moon in the sun's manner: a softly lit disc of silver grain with a few faint
/// seas, a feathered rim and fine dots over it. Drawn, not a photograph.
struct MorningLunarArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let d = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.97, green: 0.96, blue: 0.92),
                                                      Color(red: 0.80, green: 0.82, blue: 0.88),
                                                      Color(red: 0.50, green: 0.53, blue: 0.66)],
                                             center: UnitPoint(x: 0.36, y: 0.32), startRadius: 0, endRadius: d * 0.72))
                Group {
                    Circle().frame(width: d * 0.30, height: d * 0.24).offset(x: -d * 0.12, y: -d * 0.08)
                    Circle().frame(width: d * 0.20, height: d * 0.18).offset(x: d * 0.16, y: d * 0.10)
                    Circle().frame(width: d * 0.13, height: d * 0.12).offset(x: -d * 0.04, y: d * 0.22)
                    Circle().frame(width: d * 0.09, height: d * 0.09).offset(x: d * 0.20, y: -d * 0.20)
                }
                .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.62).opacity(0.28))
                .blur(radius: d * 0.025)
            }
            .frame(width: d, height: d)
            .mask(RadialGradient(stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                 center: .center, startRadius: 0, endRadius: d / 2))
        }
        .accessibilityHidden(true)
    }
}

/// A sparse frame made from round ink impressions. Reading surfaces stay solid;
/// only the edge changes, so the pattern never sits behind a paragraph.
struct MorningDottedFrame: Shape {
    var cornerRadius: CGFloat = 10
    var spacing: CGFloat = 8
    var dotRadius: CGFloat = 0.85

    func path(in rect: CGRect) -> Path {
        // Card edges are drawn by the cards themselves now; no dotted outline.
        return Path()
    }

    private func dottedPath(in rect: CGRect) -> Path {
        let inset = max(1, dotRadius)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let radius = min(cornerRadius, bounds.width / 2, bounds.height / 2)
        let horizontal = max(0, bounds.width - 2 * radius)
        let vertical = max(0, bounds.height - 2 * radius)
        var path = Path()
        func dot(_ point: CGPoint) {
            path.addEllipse(in: CGRect(x: point.x - dotRadius, y: point.y - dotRadius,
                                      width: dotRadius * 2, height: dotRadius * 2))
        }
        func edge(from start: CGPoint, to end: CGPoint, length: CGFloat) {
            let count = max(1, Int((length / max(4, spacing)).rounded()))
            for index in 0...count {
                let t = CGFloat(index) / CGFloat(count)
                dot(CGPoint(x: start.x + (end.x - start.x) * t,
                            y: start.y + (end.y - start.y) * t))
            }
        }
        edge(from: CGPoint(x: bounds.minX + radius, y: bounds.minY), to: CGPoint(x: bounds.maxX - radius, y: bounds.minY), length: horizontal)
        edge(from: CGPoint(x: bounds.minX + radius, y: bounds.maxY), to: CGPoint(x: bounds.maxX - radius, y: bounds.maxY), length: horizontal)
        edge(from: CGPoint(x: bounds.minX, y: bounds.minY + radius), to: CGPoint(x: bounds.minX, y: bounds.maxY - radius), length: vertical)
        edge(from: CGPoint(x: bounds.maxX, y: bounds.minY + radius), to: CGPoint(x: bounds.maxX, y: bounds.maxY - radius), length: vertical)
        let corners: [(CGPoint, Double)] = [
            (CGPoint(x: bounds.maxX - radius, y: bounds.minY + radius), -90),
            (CGPoint(x: bounds.maxX - radius, y: bounds.maxY - radius), 0),
            (CGPoint(x: bounds.minX + radius, y: bounds.maxY - radius), 90),
            (CGPoint(x: bounds.minX + radius, y: bounds.minY + radius), 180)
        ]
        let arcCount = max(2, Int((radius * .pi / 2 / max(4, spacing)).rounded()))
        for (center, degrees) in corners {
            for index in 1..<arcCount {
                let angle = (degrees + Double(index) / Double(arcCount) * 90) * .pi / 180
                dot(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
        }
        return path
    }
}

/// A small printed landscape. Only the stars shimmer; the sky's position changes
/// with the minute clock, so opening the app never replays the sun's journey.
struct MorningQuietLandscape: View {
    let scene: MorningCelestialScene
    var twinkles = true

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let night = scene.moon.opacity
            let ink = Color(red: 0.43 - 0.03 * night, green: 0.35 + 0.12 * night, blue: 0.25 + 0.34 * night)
            let height = min(1, max(0, (0.76 - scene.sun.centerY) / 0.58))
            let gold = Color(red: 0.95 + 0.05 * height, green: 0.40 + 0.34 * height, blue: 0.15 + 0.17 * height)
            ZStack {
                // Both bodies sit behind the horizon and trees.
                MorningDottedDisc()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.87, blue: 0.52), gold], startPoint: .top, endPoint: .bottom))
                    .frame(width: 58, height: 58)
                    .position(x: size.width * scene.sun.centerX, y: size.height * scene.sun.centerY)
                    .opacity(scene.sun.opacity)
                MorningDottedDisc(kind: .moon)
                    .fill(Color(red: 0.90, green: 0.89, blue: 0.77))
                    .frame(width: 42, height: 42)
                    .position(x: size.width * scene.moon.centerX, y: size.height * scene.moon.centerY)
                    .opacity(night)
            }
            .mask(alignment: .top) { Rectangle().frame(height: size.height * 0.765) }

            TimelineView(.animation(minimumInterval: 0.125, paused: !twinkles || night < 0.01)) { timeline in
                Canvas { context, canvas in
                    let stars: [(Double, Double, Double)] = [
                        (0.10, 0.16, 0.4), (0.23, 0.34, 1.8), (0.34, 0.09, 3.2),
                        (0.49, 0.29, 0.9), (0.62, 0.12, 4.4), (0.76, 0.33, 2.6),
                        (0.88, 0.12, 5.1), (0.94, 0.47, 1.4), (0.42, 0.48, 3.8)
                    ]
                    let seconds = twinkles ? timeline.date.timeIntervalSinceReferenceDate : 0
                    for (index, star) in stars.enumerated() {
                        let brightness = twinkles ? 0.52 + 0.28 * sin(seconds * 0.75 + star.2) : 0.68
                        let point = CGPoint(x: canvas.width * star.0, y: canvas.height * star.1)
                        var dots = Path()
                        let radius = index.isMultiple(of: 3) ? 1.25 : 0.85
                        dots.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                        if index.isMultiple(of: 3) {
                            for distance in [3.5, 6.0] {
                                for axis in [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)] {
                                    let r = distance < 4 ? 0.65 : 0.4
                                    dots.addEllipse(in: CGRect(x: point.x + axis.x * distance - r, y: point.y + axis.y * distance - r, width: r * 2, height: r * 2))
                                }
                            }
                        }
                        context.fill(dots, with: .color(Color(red: 0.92, green: 0.91, blue: 0.83).opacity(brightness * night)))
                    }
                }
            }
            Canvas { context, canvas in
                let horizon = canvas.height * 0.76
                var land = Path()
                func dot(_ x: Double, _ y: Double, _ radius: Double) {
                    land.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
                // A low, irregular dotted hill, with sparse grain beneath it.
                for column in 0...82 {
                    let x = canvas.width * Double(column) / 82
                    let edge = sin(Double(column) * 0.12) * 1.6
                    dot(x, horizon + edge, 0.7)
                    if column.isMultiple(of: 3) { dot(x + 1, horizon + 9 + sin(Double(column)) * 3, 0.45) }
                    if column.isMultiple(of: 5) { dot(x - 2, horizon + 19 + cos(Double(column)) * 4, 0.35) }
                }
                // A pair of trees on either side, entirely made of round impressions.
                for (fraction, scale) in [(0.09, 0.72), (0.18, 1.0), (0.82, 0.88), (0.91, 0.63)] {
                    let x = canvas.width * fraction
                    let base = horizon - 1
                    for row in 0...10 { dot(x, base - Double(row) * 3.2 * scale, 0.8 * scale) }
                    for row in 0...12 {
                        let y = base - (21 + Double(row) * 2.4) * scale
                        let halfWidth = sqrt(max(0, 1 - pow((Double(row) - 6) / 6.6, 2))) * 17 * scale
                        for column in -7...7 {
                            let dx = Double(column) * 2.7 * scale
                            guard abs(dx) <= halfWidth else { continue }
                            let grain = Double((row * 13 + (column + 7) * 7) % 9) / 9
                            dot(x + dx, y, (0.55 + grain * 0.45) * scale)
                        }
                    }
                    for side in [-1.0, 1.0] {
                        for step in 0...4 { dot(x + side * Double(step) * 2, base - (19 + Double(step) * 1.8) * scale, 0.7 * scale) }
                    }
                }
                // A few blades of grass give the ground a scale without filling the page.
                for fraction in [0.29, 0.34, 0.66, 0.72] {
                    let x = canvas.width * fraction
                    for step in 0...2 { dot(x + Double(step), horizon - Double(step) * 2, 0.55) }
                }
                context.fill(land, with: .color(ink.opacity(0.76)))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct MorningQuietSky: View {
    var night: Double
    var body: some View {
        ZStack {
            Color(red: 1, green: 0.97, blue: 0.90)
            Color(red: 0.055, green: 0.065, blue: 0.12).opacity(night)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
