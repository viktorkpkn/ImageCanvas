import Foundation

@MainActor
final class BoardStore: ObservableObject {
    @Published private(set) var board: BoardProject
    @Published private(set) var recents: [RecentBoard]
    @Published private(set) var pendingFolderItems: [BoardItem] = []

    let imageCache = ImageCache()

    private let appSupportURL: URL
    private let boardsURL: URL
    private let recentsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var folderImportToken = UUID()
    private var scannedFolderBoardID: UUID?
    private var scannedFolderItemsByPath: [String: BoardItem] = [:]

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

        Task { [weak self] in
            self?.scanCurrentFolderForUpdates()
        }
    }

    func newBoard() {
        clearFolderScanState()
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

        if loaded.sourceKind == .folder, let sourceFolderPath = loaded.sourceFolderPath {
            let folderURL = URL(fileURLWithPath: sourceFolderPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                recents.removeAll { $0.id == recent.id }
                saveRecents()
                return
            }

            activateBoard(loaded)
            scanFolderForUpdates(
                folderURL,
                includeSubfolders: loaded.includeSubfolders,
                boardID: loaded.id
            )
            return
        }

        activateBoard(loaded)
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
        let folderPath = folderURL.standardizedFileURL.path

        if var savedBoard = savedFolderBoard(for: folderPath) {
            let folderName = folderURL.lastPathComponent.isEmpty ? "Image Folder" : folderURL.lastPathComponent
            let didChangeSettings = savedBoard.name != folderName
                || savedBoard.includeSubfolders != includeSubfolders
                || savedBoard.sourceFolderPath != folderPath

            savedBoard.name = folderName
            savedBoard.sourceKind = .folder
            savedBoard.sourceFolderPath = folderPath
            savedBoard.includeSubfolders = includeSubfolders
            if didChangeSettings {
                savedBoard.updatedAt = Date()
            }

            activateBoard(savedBoard, save: didChangeSettings)
            scanFolderForUpdates(
                folderURL,
                includeSubfolders: includeSubfolders,
                boardID: savedBoard.id
            )
            return
        }

        importNewFolder(folderURL, includeSubfolders: includeSubfolders)
    }

    func scanCurrentFolderForUpdates() {
        guard board.sourceKind == .folder, let folderPath = board.sourceFolderPath else {
            clearFolderScanState()
            return
        }

        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            pendingFolderItems = []
            return
        }

        scanFolderForUpdates(
            folderURL,
            includeSubfolders: board.includeSubfolders,
            boardID: board.id
        )
    }

    private func importNewFolder(_ folderURL: URL, includeSubfolders: Bool) {
        let importToken = UUID()
        folderImportToken = importToken
        scannedFolderBoardID = nil
        scannedFolderItemsByPath = [:]
        pendingFolderItems = []

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

            var next = BoardProject.empty()
            next.name = folderName
            next.sourceKind = .folder
            next.sourceFolderPath = folderPath
            next.includeSubfolders = includeSubfolders
            next.knownFolderImagePaths = items.map(\.filePath).sorted()
            next.items = LayoutEngine.picasaLayout(items: items)
            next.layoutMode = .picasa
            next.updatedAt = Date()

            board = next
            scannedFolderBoardID = next.id
            scannedFolderItemsByPath = Dictionary(uniqueKeysWithValues: items.map { ($0.filePath, $0) })
            imageCache.warmThumbnails(for: next.items)
            saveCurrentBoard()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .imageCanvasFitAll, object: nil)
            }
        }
    }

    private func scanFolderForUpdates(
        _ folderURL: URL,
        includeSubfolders: Bool,
        boardID: UUID
    ) {
        let importToken = UUID()
        folderImportToken = importToken

        Task {
            let items: [BoardItem] = await Task.detached(priority: .utility) { () -> [BoardItem] in
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

            guard folderImportToken == importToken, board.id == boardID else { return }

            scannedFolderBoardID = boardID
            scannedFolderItemsByPath = Dictionary(uniqueKeysWithValues: items.map { ($0.filePath, $0) })

            if board.knownFolderImagePaths == nil {
                var migratedBoard = board
                migratedBoard.knownFolderImagePaths = board.items
                    .filter(\.isImage)
                    .map(\.filePath)
                    .sorted()
                board = migratedBoard
                saveCurrentBoard()
            }

            refreshPendingFolderItems()
        }
    }

    private func refreshPendingFolderItems() {
        guard scannedFolderBoardID == board.id, board.sourceKind == .folder else {
            pendingFolderItems = []
            return
        }

        let existingPaths = Set(board.items.filter(\.isImage).map(\.filePath))
        let knownPaths = Set(board.knownFolderImagePaths ?? Array(existingPaths))
        let nextItems = scannedFolderItemsByPath.values
            .filter { !existingPaths.contains($0.filePath) && !knownPaths.contains($0.filePath) }
            .sorted { $0.filePath.localizedStandardCompare($1.filePath) == .orderedAscending }

        guard nextItems.map(\.filePath) != pendingFolderItems.map(\.filePath) else { return }

        pendingFolderItems = nextItems
        imageCache.warmThumbnails(for: nextItems)
    }

    private func activateBoard(_ nextBoard: BoardProject, save: Bool = false) {
        clearFolderScanState()
        board = nextBoard
        imageCache.warmThumbnails(for: nextBoard.items)

        if save {
            saveCurrentBoard()
        } else {
            touchRecent(for: nextBoard)
        }
    }

    private func savedFolderBoard(for folderPath: String) -> BoardProject? {
        let normalizedPath = normalizedFolderPath(folderPath)

        if board.sourceKind == .folder,
           let currentPath = board.sourceFolderPath,
           normalizedFolderPath(currentPath) == normalizedPath {
            return board
        }

        var candidatesByID: [UUID: BoardProject] = [:]

        for recent in recents {
            guard let candidate = Self.loadBoard(
                from: URL(fileURLWithPath: recent.boardPath),
                decoder: decoder
            ) else { continue }
            candidatesByID[candidate.id] = candidate
        }

        let boardFiles = (try? FileManager.default.contentsOfDirectory(
            at: boardsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for boardFile in boardFiles where boardFile.pathExtension.lowercased() == "json" {
            guard let candidate = Self.loadBoard(from: boardFile, decoder: decoder) else { continue }
            candidatesByID[candidate.id] = candidate
        }

        return candidatesByID.values
            .filter { candidate in
                candidate.sourceKind == .folder
                    && candidate.sourceFolderPath.map(normalizedFolderPath) == normalizedPath
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func normalizedFolderPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    private func clearFolderScanState() {
        folderImportToken = UUID()
        scannedFolderBoardID = nil
        scannedFolderItemsByPath = [:]
        pendingFolderItems = []
    }

    func replaceBoard(_ nextBoard: BoardProject) {
        let didSwitchBoards = nextBoard.id != board.id
        var copy = nextBoard
        copy.updatedAt = Date()

        if didSwitchBoards {
            clearFolderScanState()
        }

        board = copy
        refreshPendingFolderItems()
        saveCurrentBoard()

        if didSwitchBoards {
            scanCurrentFolderForUpdates()
        }
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
        if next.items.isEmpty && next.sourceKind != .folder {
            next.name = inferredLooseBoardName(from: urls)
            next.sourceKind = .looseFiles
            next.sourceFolderPath = nil
            next.includeSubfolders = false
            next.knownFolderImagePaths = nil
        }

        next.items = LayoutEngine.appendedLayout(existingItems: next.items, newItems: newItems)
        if next.sourceKind == .folder {
            let knownPaths = Set(next.knownFolderImagePaths ?? Array(currentPaths))
            next.knownFolderImagePaths = Array(knownPaths.union(newItems.map(\.filePath))).sorted()
        }
        next.updatedAt = Date()
        board = next
        refreshPendingFolderItems()
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
