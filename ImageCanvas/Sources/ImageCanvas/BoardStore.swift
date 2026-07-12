import Foundation

@MainActor
final class BoardStore: ObservableObject {
    @Published private(set) var board: BoardProject
    @Published private(set) var recents: [RecentBoard]

    let imageCache = ImageCache()

    private let appSupportURL: URL
    private let boardsURL: URL
    private let recentsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var folderImportToken = UUID()

    init() {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ImageCanvas", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ImageCanvas", isDirectory: true)

        appSupportURL = baseURL
        boardsURL = baseURL.appendingPathComponent("Boards", isDirectory: true)
        recentsURL = baseURL.appendingPathComponent("recents.json")

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        jsonEncoder.dateEncodingStrategy = .iso8601
        encoder = jsonEncoder

        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        decoder = jsonDecoder

        try? fileManager.createDirectory(at: boardsURL, withIntermediateDirectories: true)

        let loadedRecents = Self.loadRecents(from: recentsURL, decoder: jsonDecoder)
        recents = loadedRecents
        board = loadedRecents.compactMap { recent in
            Self.loadBoard(from: URL(fileURLWithPath: recent.boardPath), decoder: jsonDecoder)
        }.first ?? .empty()
        imageCache.warmThumbnails(for: board.items)
    }

    func newBoard() {
        board = .empty()
        saveCurrentBoard()
    }

    func addImagesUsingPanel() {
        guard let urls = ImportPanel.pickImages() else { return }
        addFiles(urls)
    }

    func openFolderUsingPanel() {
        guard let selection = ImportPanel.pickFolder() else { return }
        openFolder(selection.url, includeSubfolders: selection.includeSubfolders)
    }

    func openRecent(_ recent: RecentBoard) {
        guard let loaded = Self.loadBoard(from: URL(fileURLWithPath: recent.boardPath), decoder: decoder) else {
            recents.removeAll { $0.id == recent.id }
            saveRecents()
            return
        }

        if loaded.sourceKind == .folder,
           let sourceFolderPath = loaded.sourceFolderPath {
            let folderURL = URL(fileURLWithPath: sourceFolderPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                recents.removeAll { $0.id == recent.id }
                saveRecents()
                return
            }

            importFolder(
                folderURL,
                includeSubfolders: loaded.includeSubfolders,
                restoring: loaded
            )
            return
        }

        board = loaded
        imageCache.warmThumbnails(for: loaded.items)
        touchRecent(for: loaded)
    }

    func clearRecents() {
        recents.removeAll()
        saveRecents()
    }

    func addFiles(_ urls: [URL]) {
        let resolvedURLs = resolveDroppedURLs(urls)
        appendImages(from: resolvedURLs)
    }

    func openFolder(_ folderURL: URL, includeSubfolders: Bool) {
        importFolder(folderURL, includeSubfolders: includeSubfolders, restoring: nil)
    }

    private func importFolder(
        _ folderURL: URL,
        includeSubfolders: Bool,
        restoring savedBoard: BoardProject?
    ) {
        let importToken = UUID()
        folderImportToken = importToken

        let folderPath = folderURL.standardizedFileURL.path
        let folderName = folderURL.lastPathComponent.isEmpty ? "Image Folder" : folderURL.lastPathComponent

        Task {
            let items: [BoardItem] = await Task.detached(priority: .userInitiated) { () -> [BoardItem] in
                let didAccess = folderURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        folderURL.stopAccessingSecurityScopedResource()
                    }
                }

                let imageURLs = ImageImporting.imageURLs(in: folderURL, includeSubfolders: includeSubfolders)
                return imageURLs.compactMap { url -> BoardItem? in
                    guard let metadata = ImageImporting.metadata(for: url) else { return nil }
                    return BoardItem(fileURL: url, pixelWidth: metadata.pixelWidth, pixelHeight: metadata.pixelHeight)
                }
            }.value

            guard folderImportToken == importToken else { return }

            var next = savedBoard ?? .empty()
            next.name = folderName
            next.sourceKind = .folder
            next.sourceFolderPath = folderPath
            next.includeSubfolders = includeSubfolders
            next.items = LayoutEngine.picasaLayout(items: items)
            next.layoutMode = .picasa
            next.updatedAt = Date()

            board = next
            imageCache.warmThumbnails(for: next.items)
            saveCurrentBoard()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .imageCanvasFitAll, object: nil)
            }
        }
    }

    func replaceBoard(_ nextBoard: BoardProject) {
        var copy = nextBoard
        copy.updatedAt = Date()
        board = copy
        saveCurrentBoard()
    }

    func saveCurrentBoard() {
        let boardURL = url(for: board.id)

        do {
            let data = try encoder.encode(board)
            try data.write(to: boardURL, options: [.atomic])
            touchRecent(for: board, boardURL: boardURL)
        } catch {
            NSLog("ImageCanvas save failed: \(error.localizedDescription)")
        }
    }

    private func appendImages(from urls: [URL]) {
        let currentPaths = Set(board.items.filter(\.isImage).map(\.filePath))
        let newItems = makeItems(from: urls)
            .filter { !currentPaths.contains($0.filePath) }

        guard !newItems.isEmpty else { return }

        var next = board
        if next.items.isEmpty {
            next.name = inferredLooseBoardName(from: urls)
            next.sourceKind = .looseFiles
            next.sourceFolderPath = nil
            next.includeSubfolders = false
        }

        next.items = LayoutEngine.appendedLayout(existingItems: next.items, newItems: newItems)
        next.updatedAt = Date()
        board = next
        imageCache.warmThumbnails(for: newItems)
        saveCurrentBoard()
    }

    private func makeItems(from urls: [URL]) -> [BoardItem] {
        ImageImporting.imageURLs(from: urls).compactMap { url in
            guard let metadata = ImageImporting.metadata(for: url) else { return nil }
            return BoardItem(fileURL: url, pixelWidth: metadata.pixelWidth, pixelHeight: metadata.pixelHeight)
        }
    }

    private func resolveDroppedURLs(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                return ImageImporting.imageURLs(in: url, includeSubfolders: false)
            }

            return [url]
        }
    }

    private func inferredLooseBoardName(from urls: [URL]) -> String {
        if urls.count == 1, let first = urls.first {
            return first.deletingPathExtension().lastPathComponent
        }

        return "Image Board"
    }

    private func touchRecent(for board: BoardProject, boardURL: URL? = nil) {
        let resolvedURL = boardURL ?? url(for: board.id)
        let recent = RecentBoard(
            id: board.id,
            name: board.name,
            boardPath: resolvedURL.path,
            updatedAt: board.updatedAt
        )

        recents.removeAll { $0.id == recent.id }
        recents.insert(recent, at: 0)
        recents = Array(recents.prefix(10))
        saveRecents()
    }

    private func saveRecents() {
        do {
            let data = try encoder.encode(recents)
            try data.write(to: recentsURL, options: [.atomic])
        } catch {
            NSLog("ImageCanvas recents save failed: \(error.localizedDescription)")
        }
    }

    private func url(for boardID: UUID) -> URL {
        boardsURL.appendingPathComponent("\(boardID.uuidString).json")
    }

    private static func loadRecents(from url: URL, decoder: JSONDecoder) -> [RecentBoard] {
        guard let data = try? Data(contentsOf: url),
              let recents = try? decoder.decode([RecentBoard].self, from: data) else {
            return []
        }

        return Array(recents.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
    }

    private static func loadBoard(from url: URL, decoder: JSONDecoder) -> BoardProject? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(BoardProject.self, from: data)
    }
}
