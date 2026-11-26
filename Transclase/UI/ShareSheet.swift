import SwiftUI

#if os(iOS)
import UIKit

/// Wraps `UIActivityViewController` so a share can be triggered by a plain
/// button: `ShareLink` builds its payload while the view renders, which is
/// expensive for a long transcript.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
