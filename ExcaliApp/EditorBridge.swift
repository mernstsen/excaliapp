import AppKit
import Observation
import WebKit

/// Owns the single Excalidraw web view and decides when its scene reaches disk.
///
/// Autosave has two clocks: a quiet period so a save lands shortly after you
/// stop, and a ceiling so a long uninterrupted drawing session still gets
/// checkpointed. A save is also forced when switching drawings and on quit.
@Observable
@MainActor
final class EditorBridge {
    enum Status: Equatable {
        case empty
        case clean
        case edited
        case saving
        case failed(String)
    }

    private static let quietPeriod: TimeInterval = 1.5
    private static let ceiling: TimeInterval = 10
    private static let messageName = "excaliapp"

    let webView: WKWebView

    private(set) var status: Status = .empty
    private(set) var current: Drawing?
    private(set) var lastSaved: Date?

    var hasUnsavedChanges: Bool { needsSave }

    private var isReady = false
    private var needsSave = false
    private var theme = "light"
    private var firstEditAt: Date?
    private var autosave: Task<Void, Never>?
    private var saveChain: Task<Void, Never>?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            WebBundleSchemeHandler(),
            forURLScheme: WebBundleSchemeHandler.scheme
        )

        let proxy = MessageProxy()
        configuration.userContentController.add(proxy, name: Self.messageName)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = false
        webView.underPageBackgroundColor = .windowBackgroundColor
        #if DEBUG
        webView.isInspectable = true
        #endif

        proxy.bridge = self
        webView.load(URLRequest(url: WebBundleSchemeHandler.entryPoint))
    }

    // MARK: - Documents

    /// Saves whatever is open, then swaps in `drawing`.
    func open(_ drawing: Drawing?) {
        Task { await openAndWait(drawing) }
    }

    func openAndWait(_ drawing: Drawing?) async {
        guard drawing?.url != current?.url else { return }
        await flush()

        current = drawing
        needsSave = false
        firstEditAt = nil
        autosave?.cancel()
        autosave = nil

        await loadCurrentScene()
    }

    /// Re-points at the same scene after a rename, without a reload.
    func reattach(to drawing: Drawing) {
        current = drawing
    }

    /// Drops the open document and any edits still owed to it. Used when that
    /// document is being deleted, so a queued save cannot recreate the file.
    func abandon() {
        autosave?.cancel()
        autosave = nil
        needsSave = false
        firstEditAt = nil
        current = nil
        status = .empty
    }

    private func loadCurrentScene() async {
        guard isReady else {
            status = current == nil ? .empty : .clean
            return
        }

        let json: String
        if let drawing = current {
            guard let contents = try? String(contentsOf: drawing.url, encoding: .utf8) else {
                status = .failed("Could not read \(drawing.name).")
                return
            }
            json = contents
        } else {
            json = ""
        }

        do {
            _ = try await webView.callAsyncJavaScript(
                "window.excaliApp.loadScene(json)",
                arguments: ["json": json],
                contentWorld: .page
            )
            status = current == nil ? .empty : .clean
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Saving

    /// Writes immediately if there is anything to write.
    func flush() async {
        autosave?.cancel()
        autosave = nil
        await enqueueSave()
    }

    /// Serialises saves so a forced flush cannot overlap a running autosave.
    private func enqueueSave() async {
        let previous = saveChain
        let task = Task { [weak self] in
            await previous?.value
            await self?.performSave()
        }
        saveChain = task
        await task.value
    }

    private func performSave() async {
        guard needsSave, isReady, let drawing = current else { return }

        status = .saving
        do {
            let result = try await webView.callAsyncJavaScript(
                "return window.excaliApp.getSceneJSON();",
                contentWorld: .page
            )
            guard let json = result as? String else {
                throw CocoaError(.fileWriteUnknown)
            }

            let destination = drawing.url
            try await Task.detached(priority: .utility) {
                try Data(json.utf8).write(to: destination, options: .atomic)
            }.value

            // Only now does the canvas consider itself saved; anything drawn
            // during the write stays pending.
            let stillDirty = try await webView.callAsyncJavaScript(
                "return window.excaliApp.markSaved();",
                contentWorld: .page
            ) as? Bool ?? false

            lastSaved = Date()
            needsSave = stillDirty
            firstEditAt = stillDirty ? Date() : nil
            status = stillDirty ? .edited : .clean
            if stillDirty {
                scheduleAutosave()
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        let elapsed = firstEditAt.map { Date().timeIntervalSince($0) } ?? 0
        let delay = max(0, min(Self.quietPeriod, Self.ceiling - elapsed))

        autosave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.enqueueSave()
        }
    }

    // MARK: - Appearance

    func setDarkMode(_ isDark: Bool) {
        theme = isDark ? "dark" : "light"
        guard isReady else { return }
        Task { await applyTheme() }
    }

    private func applyTheme() async {
        _ = try? await webView.callAsyncJavaScript(
            "window.excaliApp.setTheme(theme)",
            arguments: ["theme": theme],
            contentWorld: .page
        )
    }

    // MARK: - Messages from the canvas

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any],
              let type = message["type"] as? String
        else { return }

        switch type {
        case "ready":
            isReady = true
            Task {
                await applyTheme()
                await loadCurrentScene()
            }
        case "dirty":
            guard current != nil else { return }
            needsSave = true
            status = .edited
            if firstEditAt == nil {
                firstEditAt = Date()
            }
            scheduleAutosave()
        case "clean":
            needsSave = false
            firstEditAt = nil
            autosave?.cancel()
            autosave = nil
            status = current == nil ? .empty : .clean
        default:
            break
        }
    }
}

/// Keeps `WKUserContentController`'s strong reference off the bridge itself.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var bridge: EditorBridge?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            bridge?.receive(message.body)
        }
    }
}
