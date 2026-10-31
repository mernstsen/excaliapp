import SwiftUI

/// The library mutations the sidebar and the File menu both perform.
struct LibraryActions {
    let store: DrawingStore
    let bridge: EditorBridge
    @Binding var selection: Drawing.ID?
    @Binding var renaming: Drawing.ID?

    var selected: Drawing? {
        store.drawings.first { $0.id == selection }
    }

    func newDrawing() {
        guard let drawing = store.create() else { return }
        selection = drawing.id
        renaming = drawing.id
    }

    func duplicate(_ drawing: Drawing) {
        guard let copy = store.duplicate(drawing) else { return }
        selection = copy.id
    }

    func rename(_ drawing: Drawing, to newName: String) {
        renaming = nil
        guard let renamed = store.rename(drawing, to: newName) else { return }
        // The file moved; keep editing it instead of reloading the canvas.
        if bridge.current?.url == drawing.url {
            bridge.reattach(to: renamed)
        }
        if selection == drawing.id {
            selection = renamed.id
        }
    }

    func delete(_ drawing: Drawing) {
        // Let go of pending edits first, or the queued save would write the
        // file straight back after it is trashed.
        if bridge.current?.url == drawing.url {
            bridge.abandon()
        }
        let wasSelected = selection == drawing.id
        store.delete(drawing)
        if wasSelected {
            selection = store.drawings.first?.id
        }
    }

    func reveal(_ drawing: Drawing) {
        store.reveal(drawing)
    }
}
