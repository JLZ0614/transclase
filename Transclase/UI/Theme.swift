import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    static var appBackground: Color {
        #if os(macOS)
        // `underPageBackgroundColor` is the soft grey macOS uses behind content;
        // plain windowBackground reads as glaring white at this window size.
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
                // Light appearance: flat white. The coloured washes made the
                // page look like a blue-white gradient rather than paper.
                Color.white
            }
        }
        .ignoresSafeArea()
    }
}

/// Five-bar input meter, in the spirit of Voice Memos.
struct LevelBars: View {
    @ObservedObject var meter: AudioLevelMeter
    var height: CGFloat = 20
    private let weights: [CGFloat] = [0.55, 0.95, 0.75, 1.0, 0.6]

    var body: some View {
        let amplitude = CGFloat(min(max(meter.level, 0), 1))
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(weights.enumerated()), id: \.offset) { _, weight in
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 2.5, height: max(2.5, height * amplitude * weight))
            }
        }
        .frame(width: 20, height: height)
        .animation(.easeOut(duration: 0.1), value: meter.level)
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


/// App 图标的矢量版本：磨砂玻璃方块 + 三根青蓝渐变柱。
/// 用于工具栏和空状态，保证界面和应用图标是同一个标志。
struct BrandMark: View {
    var size: CGFloat = 26

    private let top = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let bottom = Color(red: 0.15, green: 0.39, blue: 0.92)

    private var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private func bar(_ factor: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
            .fill(gradient)
            .frame(width: size * 0.155, height: size * 0.56 * factor)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 0.91, green: 0.94, blue: 0.985)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }

            HStack(spacing: size * 0.085) {
                bar(0.62)
                bar(1.0)
                bar(0.62)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}


/// 只画三根柱子，无底板、透明背景——用于工具栏这类小尺寸场景。
struct BrandGlyph: View {
    var size: CGFloat = 26

    private let top = Color(red: 0.40, green: 0.91, blue: 0.98)
    private let bottom = Color(red: 0.15, green: 0.39, blue: 0.92)

    private var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private func bar(_ factor: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.085, style: .continuous)
            .fill(gradient)
            .frame(width: size * 0.20, height: size * 0.86 * factor)
    }

    var body: some View {
        HStack(spacing: size * 0.115) {
            bar(0.62)
            bar(1.0)
            bar(0.62)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
