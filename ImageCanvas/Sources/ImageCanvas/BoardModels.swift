import CoreGraphics
import Foundation

enum BoardSourceKind: String, Codable, Equatable {
    case looseFiles
    case folder
}

enum LayoutMode: String, Codable, CaseIterable, Equatable {
    case picasa
    case pinterest

    var title: String {
        switch self {
        case .picasa: "Tiled grid"
        case .pinterest: "Cascading grid"
        }
    }
}

enum BoardItemKind: String, Codable, Equatable {
    case image
    case text
}

struct CanvasRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct BoardItem: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: BoardItemKind
    var filePath: String
    var fileName: String
    var pixelWidth: CGFloat
    var pixelHeight: CGFloat
    var frame: CanvasRect
    var rotationDegrees: Int
    var isFlippedHorizontally: Bool
    var isFlippedVertically: Bool
    var text: String?
    var isBold: Bool
    var isItalic: Bool

    init(fileURL: URL, pixelWidth: CGFloat, pixelHeight: CGFloat) {
        id = UUID()
        kind = .image
        filePath = fileURL.standardizedFileURL.path
        fileName = fileURL.lastPathComponent
        self.pixelWidth = max(pixelWidth, 1)
        self.pixelHeight = max(pixelHeight, 1)
        frame = CanvasRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        rotationDegrees = 0
        isFlippedHorizontally = false
        isFlippedVertically = false
        text = nil
        isBold = false
        isItalic = false
    }

    init(text: String = "", at point: CGPoint) {
        id = UUID()
        kind = .text
        filePath = ""
        fileName = "Text"
        pixelWidth = 280
        pixelHeight = 100
        frame = CanvasRect(x: point.x, y: point.y, width: 280, height: 100)
        rotationDegrees = 0
        isFlippedHorizontally = false
        isFlippedVertically = false
        self.text = text
        isBold = false
        isItalic = false
    }

    var aspectRatio: CGFloat {
        max(pixelWidth, 1) / max(pixelHeight, 1)
    }

    var isImage: Bool {
        kind == .image
    }

    var isText: Bool {
        kind == .text
    }

    var displayedText: String {
        text ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case filePath
        case fileName
        case pixelWidth
        case pixelHeight
        case frame
        case rotationDegrees
        case isFlippedHorizontally
        case isFlippedVertically
        case text
        case isBold
        case isItalic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedText = try container.decodeIfPresent(String.self, forKey: .text)

        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(BoardItemKind.self, forKey: .kind)
            ?? (decodedText == nil ? .image : .text)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? ""
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
            ?? (kind == .text ? "Text" : "Image")
        pixelWidth = try container.decodeIfPresent(CGFloat.self, forKey: .pixelWidth) ?? 1
        pixelHeight = try container.decodeIfPresent(CGFloat.self, forKey: .pixelHeight) ?? 1
        frame = try container.decode(CanvasRect.self, forKey: .frame)
        rotationDegrees = try container.decodeIfPresent(Int.self, forKey: .rotationDegrees) ?? 0
        isFlippedHorizontally = try container.decodeIfPresent(Bool.self, forKey: .isFlippedHorizontally) ?? false
        isFlippedVertically = try container.decodeIfPresent(Bool.self, forKey: .isFlippedVertically) ?? false
        text = decodedText
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
    }
}

struct ViewportState: Codable, Equatable {
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat

    static let initial = ViewportState(scale: 1, offsetX: 0, offsetY: 0)
}

struct BoardProject: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var sourceKind: BoardSourceKind
    var sourceFolderPath: String?
    var includeSubfolders: Bool
    var layoutMode: LayoutMode
    var items: [BoardItem]
    var viewport: ViewportState
    var createdAt: Date
    var updatedAt: Date

    static func empty() -> BoardProject {
        let now = Date()
        return BoardProject(
            id: UUID(),
            name: "Untitled Board",
            sourceKind: .looseFiles,
            sourceFolderPath: nil,
            includeSubfolders: false,
            layoutMode: .picasa,
            items: [],
            viewport: .initial,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct RecentBoard: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var boardPath: String
    var updatedAt: Date
}

struct ImageMetadata: Equatable {
    var pixelWidth: CGFloat
    var pixelHeight: CGFloat
}
