import AppKit
import Foundation
import Observation

struct Drawing: Identifiable, Hashable {
    let url: URL
    let modified: Date

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// The library: every `.excalidraw` file in one folder, newest first.
@Observable
@MainActor
final class DrawingStore {
    static let fileExtension = "excalidraw"
    private static let folderKey = "LibraryFolderPath"

    private(set) var drawings: [Drawing] = []
    private(set) var folder: URL
    private(set) var failure: String?

    private var watcher: DispatchSourceFileSystemObject?
    private var reloadTask: Task<Void, Never>?

    init() {
        folder = Self.storedFolder() ?? Self.defaultFolder
        prepareFolder()
        reload()
        startWatching()
    }

    // MARK: - Folder

    static var defaultFolder: URL {
        URL.documentsDirectory.appending(path: "Excalidraw", directoryHint: .isDirectory)
    }

    private static func storedFolder() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: folderKey) else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    func setFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
        folder = url
        prepareFolder()
        reload()
        startWatching()
    }

    private func prepareFolder() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Everything the store hands out is standardised, so URLs built
            // from the folder compare equal to enumerated ones.
            folder = folder.standardizedFileURL
            failure = nil
        } catch {
            failure = "Could not open \(folder.path): \(error.localizedDescription)"
        }
    }

    // MARK: - Reading

    func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []

        drawings = contents
            .filter { $0.pathExtension.lowercased() == Self.fileExtension }
            .map {
                let modified = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return Drawing(url: $0.standardizedFileURL, modified: modified ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// Picks up drawings added, renamed or deleted behind the app's back.
    private func startWatching() {
        watcher?.cancel()
        watcher = nil

        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func drawing(at url: URL) -> Drawing? {
        let target = url.standardizedFileURL.path
        return drawings.first { $0.url.standardizedFileURL.path == target }
    }

    // MARK: - Writing

    private static let emptyScene = """
        {"type":"excalidraw","version":2,"source":"ExcaliApp",\
        "elements":[],"appState":{"viewBackgroundColor":"#ffffff"},"files":{}}
        """

    @discardableResult
    func create(named name: String = "Untitled") -> Drawing? {
        let url = uniqueURL(for: name)
        do {
            try Data(Self.emptyScene.utf8).write(to: url, options: .withoutOverwriting)
        } catch {
            failure = "Could not create drawing: \(error.localizedDescription)"
            return nil
        }
        reload()
        return drawing(at: url)
    }

    @discardableResult
    func rename(_ drawing: Drawing, to newName: String) -> Drawing? {
        let trimmed = Self.sanitize(newName)
        guard !trimmed.isEmpty, trimmed != drawing.name else { return drawing }

        let destination = uniqueURL(for: trimmed)
        do {
            try FileManager.default.moveItem(at: drawing.url, to: destination)
        } catch {
            failure = "Could not rename: \(error.localizedDescription)"
            return nil
        }
        reload()
        return self.drawing(at: destination)
    }

    @discardableResult
    func duplicate(_ drawing: Drawing) -> Drawing? {
        let destination = uniqueURL(for: drawing.name + " copy")
        do {
            try FileManager.default.copyItem(at: drawing.url, to: destination)
        } catch {
            failure = "Could not duplicate: \(error.localizedDescription)"
            return nil
        }
        reload()
        return self.drawing(at: destination)
    }

    /// Moves to the Trash rather than unlinking, so Cmd-Z in Finder still works.
    func delete(_ drawing: Drawing) {
        do {
            try FileManager.default.trashItem(at: drawing.url, resultingItemURL: nil)
        } catch {
            failure = "Could not move to Trash: \(error.localizedDescription)"
        }
        reload()
    }

    func reveal(_ drawing: Drawing) {
        NSWorkspace.shared.activateFileViewerSelecting([drawing.url])
    }

    func dismissFailure() {
        failure = nil
    }

    // MARK: - Naming

    private static func sanitize(_ name: String) -> String {
        name
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueURL(for name: String) -> URL {
        let base = Self.sanitize(name).isEmpty ? "Untitled" : Self.sanitize(name)
        var candidate = folder.appending(path: "\(base).\(Self.fileExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base) \(counter).\(Self.fileExtension)")
            counter += 1
        }
        return candidate
    }
}
