import SwiftUI

@main
struct ExcaliAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store = DrawingStore()
    @State private var bridge = EditorBridge()
    @State private var selection: Drawing.ID?
    @State private var renaming: Drawing.ID?

    var body: some Scene {
        // One window: there is a single canvas, and the sidebar is how you move
        // between drawings.
        Window("ExcaliApp", id: "main") {
            ContentView(
                store: store,
                bridge: bridge,
                selection: $selection,
                renaming: $renaming
            )
            .frame(minWidth: 720, minHeight: 480)
            .onAppear { appDelegate.bridge = bridge }
            .onChange(of: store.folder) { _, _ in
                selection = store.drawings.first?.id
            }
        }
        .commands {
            LibraryCommands(
                store: store,
                bridge: bridge,
                selection: $selection,
                renaming: $renaming
            )
            SidebarCommands()
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

private struct LibraryCommands: Commands {
    let store: DrawingStore
    let bridge: EditorBridge
    @Binding var selection: Drawing.ID?
    @Binding var renaming: Drawing.ID?

    private var actions: LibraryActions {
        LibraryActions(
            store: store,
            bridge: bridge,
            selection: $selection,
            renaming: $renaming
        )
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Drawing", action: actions.newDrawing)
                .keyboardShortcut("n")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                Task { await bridge.flush() }
            }
            .keyboardShortcut("s")
            .disabled(selection == nil)
        }

        CommandGroup(after: .saveItem) {
            Divider()

            Button("Rename…") { renaming = selection }
                .disabled(actions.selected == nil)

            Button("Duplicate") {
                guard let drawing = actions.selected else { return }
                actions.duplicate(drawing)
            }
            .keyboardShortcut("d")
            .disabled(actions.selected == nil)

            Button("Reveal in Finder") {
                guard let drawing = actions.selected else { return }
                actions.reveal(drawing)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions.selected == nil)

            Divider()

            Button("Move to Trash") {
                guard let drawing = actions.selected else { return }
                actions.delete(drawing)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(actions.selected == nil)
        }
    }
}

private struct SettingsView: View {
    let store: DrawingStore

    var body: some View {
        Form {
            LabeledContent("Drawings Folder") {
                HStack(spacing: 8) {
                    Text(store.folder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Button("Change…", action: chooseFolder)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.folder
        panel.prompt = "Choose"
        panel.message = "Choose the folder ExcaliApp keeps your drawings in."

        if panel.runModal() == .OK, let url = panel.url {
            store.setFolder(url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var bridge: EditorBridge?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Quitting must not drop the last few seconds of drawing.
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let bridge, bridge.hasUnsavedChanges else { return .terminateNow }
            Task {
                await bridge.flush()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
