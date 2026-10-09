import SwiftUI
import MorningCore

// Resolve the property wrapper explicitly when newer SDKs also expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum MorningStyle {
    static let ink = Color(red: 0.12, green: 0.19, blue: 0.24)
    static let muted = Color(red: 0.40, green: 0.45, blue: 0.47)
    static let background = Color(red: 0.975, green: 0.967, blue: 0.945)
    static let accent = Color(red: 0.85, green: 0.34, blue: 0.18)
    static let paleOrange = Color(red: 1, green: 0.91, blue: 0.81)
    static let green = Color(red: 0.24, green: 0.43, blue: 0.35)
    static let line = Color(red: 0.87, green: 0.87, blue: 0.83)

    static func symbol(for kind: StepKind) -> String {
        switch kind {
        case .briefing: "sun.horizon"
        case .messages: "bubble.left.and.bubble.right"
        case .calendar: "calendar"
        case .wellbeing: "heart"
        case .entertainment: "sparkles.tv"
        case .custom: "circle.grid.2x2"
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 21).padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(MorningStyle.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 17).padding(.vertical, 13)
            .foregroundStyle(MorningStyle.ink)
            .background(.white.opacity(configuration.isPressed ? 0.5 : 0.85), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MorningStyle.line, lineWidth: 1))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2)
            .foregroundStyle(MorningStyle.muted)
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = MorningStyle.green
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 7)
        .background(color.opacity(0.08), in: Capsule())
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(MorningStyle.line.opacity(0.65), lineWidth: 1))
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(size: 38, weight: .medium, design: .serif))
                .foregroundStyle(MorningStyle.ink)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
