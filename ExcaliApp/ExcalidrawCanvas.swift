import SwiftUI
import WebKit

/// Hosts the one long-lived web view. The instance outlives document switches,
/// so the canvas never reloads just because the selection changed.
struct ExcalidrawCanvas: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
