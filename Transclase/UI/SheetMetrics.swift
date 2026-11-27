import CoreGraphics

/// Panel size for settings and provider sheets: a fixed share of the window,
/// clamped so it never dominates the window it sits in.
enum SheetMetrics {
    static func size(for window: CGSize) -> CGSize {
        let width = min(max(420, window.width * 0.62), min(720, max(320, window.width - 80)))
        let height = min(max(320, window.height * 0.68), min(640, max(280, window.height - 80)))
        return CGSize(width: width, height: height)
    }
}
