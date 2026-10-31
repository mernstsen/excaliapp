import SwiftUI

struct SidebarView: View {
    let store: DrawingStore
    let actions: LibraryActions
    @Binding var selection: Drawing.ID?
    @Binding var renaming: Drawing.ID?
    @Binding var query: String

    private var visible: [Drawing] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.drawings }
        return store.drawings.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(visible) { drawing in
                DrawingRow(
                    drawing: drawing,
                    isRenaming: renaming == drawing.id,
                    onCommit: { actions.rename(drawing, to: $0) },
                    onCancel: { renaming = nil }
                )
                .tag(drawing.id)
                .contextMenu {
                    Button("Rename…") { renaming = drawing.id }
                    Button("Duplicate") { actions.duplicate(drawing) }
                    Button("Reveal in Finder") { actions.reveal(drawing) }
                    Divider()
                    Button("Move to Trash") { actions.delete(drawing) }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "Search Drawings")
        .overlay {
            if store.drawings.isEmpty {
                ContentUnavailableView {
                    Label("No Drawings", systemImage: "scribble.variable")
                } description: {
                    Text("Drawings you create are saved to \(store.folder.lastPathComponent).")
                } actions: {
                    Button("New Drawing", action: actions.newDrawing)
                }
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

private struct DrawingRow: View {
    let drawing: Drawing
    let isRenaming: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isRenaming {
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { onCommit(draft) }
                .onExitCommand(perform: onCancel)
                .task {
                    draft = drawing.name
                    isFocused = true
                }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(drawing.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(drawing.modified, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}
