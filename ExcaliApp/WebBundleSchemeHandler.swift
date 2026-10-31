import Foundation
import WebKit

/// Serves the bundled Excalidraw build over `excaliapp://app/`.
///
/// A custom scheme rather than `file://`: a file URL gets an opaque origin, and
/// WebKit then blocks the `fetch` and worker loads Excalidraw does at runtime.
final class WebBundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "excaliapp"
    static let entryPoint = URL(string: "\(scheme)://app/index.html")!

    private let root: URL

    init(root: URL? = Bundle.main.url(forResource: "Web", withExtension: "bundle")) {
        guard let root else {
            preconditionFailure("Web.bundle is missing from the app bundle — run `npm run build` in web/")
        }
        self.root = root.standardizedFileURL
        super.init()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        let path = url.path().isEmpty || url.path() == "/" ? "/index.html" : url.path()
        let file = root.appending(path: path).standardizedFileURL

        // Keep a malformed path from escaping the bundle.
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.contentType(for: file.pathExtension),
                "Content-Length": String(data.count),
                "Cache-Control": "no-store",
            ]
        )!

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func contentType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "woff2": "font/woff2"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        default: "application/octet-stream"
        }
    }
}
