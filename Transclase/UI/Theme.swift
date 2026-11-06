import SwiftUI

import AppKit

extension Color {
    static var appBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Quiet backdrop: system background with a single wash of colour so the glass
/// panels have something to refract.
struct AppBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // Dark appearance: pure black, no colour wash — the glass
                // panels read better against a neutral backdrop anyway.
                Color.black
            } else {
                Color.appBackground
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.13), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 720
                )
                RadialGradient(
                    colors: [Color.blue.opacity(0.06), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 560
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Five-bar input meter, in the spirit of Voice Memos.
struct LevelBars: View {
    let level: Float
    var height: CGFloat = 20
    private let weights: [CGFloat] = [0.55, 0.95, 0.75, 1.0, 0.6]

    var body: some View {
        let amplitude = CGFloat(min(max(level, 0), 1))
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(weights.enumerated()), id: \.offset) { _, weight in
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 2.5, height: max(2.5, height * amplitude * weight))
            }
        }
        .frame(width: 20, height: height)
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityLabel(L("麦克风音量"))
    }
}

struct StatusDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.secondary.opacity(0.5))
            .frame(width: 7, height: 7)
            .overlay {
                if isActive {
                    Circle()
                        .stroke(Color.green.opacity(0.45), lineWidth: 2)
                        .scaleEffect(1.9)
                }
            }
    }
}
