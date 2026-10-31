import SwiftUI

struct ContentView: View {
    let store: DrawingStore
    let bridge: EditorBridge
    @Binding var selection: Drawing.ID?
    @Binding var renaming: Drawing.ID?

    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    private var actions: LibraryActions {
        LibraryActions(
            store: store,
            bridge: bridge,
            selection: $selection,
            renaming: $renaming
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                actions: actions,
                selection: $selection,
                renaming: $renaming,
                query: $query
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 340)
        } detail: {
            // Deliberately no ignoresSafeArea: macOS floats the sidebar as
            // glass over full-width detail content, and the safe area is what
            // keeps Excalidraw's own edge panels — stroke, background, fill —
            // from ending up underneath it.
            ExcalidrawCanvas(webView: bridge.webView)
                .opacity(selection == nil ? 0 : 1)
                .overlay {
                    if selection == nil {
                        ContentUnavailableView {
                            Label("No Drawing Selected", systemImage: "scribble.variable")
                        } description: {
                            Text("Pick a drawing in the sidebar, or start a new one.")
                        } actions: {
                            Button("New Drawing", action: actions.newDrawing)
                        }
                    }
                }
        }
        .navigationTitle(bridge.current?.name ?? "ExcaliApp")
        .navigationSubtitle(statusDescription)
        .toolbar {
            ToolbarItem {
                Button(action: actions.newDrawing) {
                    Label("New Drawing", systemImage: "square.and.pencil")
                }
                .help("New Drawing")
            }
        }
        .onChange(of: selection) { _, id in
            bridge.open(store.drawings.first { $0.id == id })
            LibrarySession.lastSelectedPath = id?.path
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            bridge.setDarkMode(scheme == .dark)
        }
        .task { restoreSelection() }
        .alert(
            "Library Problem",
            isPresented: Binding(
                get: { store.failure != nil },
                set: { if !$0 { store.dismissFailure() } }
            )
        ) {
            Button("OK") { store.dismissFailure() }
        } message: {
            Text(store.failure ?? "")
        }
    }

    private var statusDescription: String {
        switch bridge.status {
        case .empty: ""
        case .clean: "Saved"
        case .edited: "Edited"
        case .saving: "Saving…"
        case .failed(let message): "Not Saved — \(message)"
        }
    }

    private func restoreSelection() {
        if store.drawings.isEmpty, !LibrarySession.didSeed {
            LibrarySession.didSeed = true
            selection = store.create()?.id
            return
        }
        let remembered = LibrarySession.lastSelectedPath.flatMap { path in
            store.drawings.first { $0.url.path == path }
        }
        selection = (remembered ?? store.drawings.first)?.id
    }
}

/// Window state that should survive a relaunch.
enum LibrarySession {
    private static let lastSelectedKey = "LastSelectedDrawing"
    private static let didSeedKey = "DidSeedLibrary"

    static var lastSelectedPath: String? {
        get { UserDefaults.standard.string(forKey: lastSelectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSelectedKey) }
    }

    static var didSeed: Bool {
        get { UserDefaults.standard.bool(forKey: didSeedKey) }
        set { UserDefaults.standard.set(newValue, forKey: didSeedKey) }
    }
}
