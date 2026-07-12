import AppKit
import SwiftUI

private struct TextFormattingControlState: Equatable {
    var itemID: UUID
    var isBold: Bool
    var isItalic: Bool
}

private struct TextFormattingGlassControl: View {
    var isBold: Bool
    var isItalic: Bool
    var onToggleBold: () -> Void
    var onToggleItalic: () -> Void

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            buttons
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .contentShape(Capsule())
                .padding(10)
        } else {
            buttons
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .contentShape(Capsule())
                .padding(10)
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            formattingButton(systemImage: "bold", isActive: isBold, action: onToggleBold)

            Rectangle()
                .fill(.white.opacity(0.24))
                .frame(width: 1, height: 20)

            formattingButton(systemImage: "italic", isActive: isItalic, action: onToggleItalic)
        }
        .padding(.horizontal, 3)
    }

    private func formattingButton(
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.white)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isActive ? "On" : "Off")
    }
}

struct CanvasViewRepresentable: NSViewRepresentable {
    var board: BoardProject
    var imageCache: ImageCache
    var isDrawingModeEnabled: Bool
    var isTextModeEnabled: Bool
    var areControlsVisible: Bool
    var drawingColor: NSColor
    var onBoardChanged: (BoardProject) -> Void
    var onAddFiles: ([URL]) -> Void
    var onToggleChrome: () -> Void
    var onDrawingModeChanged: (Bool) -> Void
    var onTextModeChanged: (Bool) -> Void
    var onCanvasInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ImageCanvasNSView {
        let view = ImageCanvasNSView()
        view.configure(
            imageCache: imageCache,
            isDrawingModeEnabled: isDrawingModeEnabled,
            isTextModeEnabled: isTextModeEnabled,
            areControlsVisible: areControlsVisible,
            drawingColor: drawingColor,
            onBoardChanged: { context.coordinator.parent.onBoardChanged($0) },
            onAddFiles: { context.coordinator.parent.onAddFiles($0) },
            onToggleChrome: { context.coordinator.parent.onToggleChrome() },
            onDrawingModeChanged: { context.coordinator.parent.onDrawingModeChanged($0) },
            onTextModeChanged: { context.coordinator.parent.onTextModeChanged($0) },
            onCanvasInteraction: { context.coordinator.parent.onCanvasInteraction() }
        )
        view.setBoard(board)
        return view
    }

    func updateNSView(_ nsView: ImageCanvasNSView, context: Context) {
        context.coordinator.parent = self
        nsView.configure(
            imageCache: imageCache,
            isDrawingModeEnabled: isDrawingModeEnabled,
            isTextModeEnabled: isTextModeEnabled,
            areControlsVisible: areControlsVisible,
            drawingColor: drawingColor,
            onBoardChanged: { context.coordinator.parent.onBoardChanged($0) },
            onAddFiles: { context.coordinator.parent.onAddFiles($0) },
            onToggleChrome: { context.coordinator.parent.onToggleChrome() },
            onDrawingModeChanged: { context.coordinator.parent.onDrawingModeChanged($0) },
            onTextModeChanged: { context.coordinator.parent.onTextModeChanged($0) },
            onCanvasInteraction: { context.coordinator.parent.onCanvasInteraction() }
        )
        nsView.setBoard(board)
    }

    final class Coordinator {
        var parent: CanvasViewRepresentable

        init(parent: CanvasViewRepresentable) {
            self.parent = parent
        }
    }
}

final class ImageCanvasNSView: NSView, NSTextFieldDelegate {
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    private enum Interaction {
        case none
        case moving(start: CGPoint, originalFrames: [UUID: CGRect])
        case resizing(id: UUID, corner: ResizeCorner, anchor: CGPoint, aspectRatio: CGFloat)
        case resizingGroup(corner: ResizeCorner, anchor: CGPoint, originalFrames: [UUID: CGRect], originalBounds: CGRect, aspectRatio: CGFloat)
        case marquee(start: CGPoint)
        case panning(lastScreenPoint: CGPoint)
        case drawing
    }

    private enum ResizeCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    private enum TextStyleAction {
        case bold
        case italic
    }

    private struct SnapGuide {
        enum Axis {
            case vertical
            case horizontal
        }

        var axis: Axis
        var position: CGFloat
    }

    private struct DrawingStroke {
        var color: NSColor
        var lineWidth: CGFloat
        var points: [CGPoint]
    }

    private var board = BoardProject.empty()
    private var imageCache: ImageCache?
    private var onBoardChanged: ((BoardProject) -> Void)?
    private var onAddFiles: (([URL]) -> Void)?
    private var onToggleChrome: (() -> Void)?
    private var onDrawingModeChanged: ((Bool) -> Void)?
    private var onTextModeChanged: ((Bool) -> Void)?
    private var onCanvasInteraction: (() -> Void)?

    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    private var selectedIDs = Set<UUID>()
    private var interaction: Interaction = .none
    private var marqueeRect: CGRect?
    private var snapGuides: [SnapGuide] = []
    private var pendingUndoSnapshot: BoardProject?
    private var undoStack: [BoardProject] = []
    private var redoStack: [BoardProject] = []
    private var isSpacePressed = false
    private var isZooming = false
    private var zoomSettleWorkItem: DispatchWorkItem?
    private var viewportCommitWorkItem: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var isDrawingModeEnabled = false
    private var isTextModeEnabled = false
    private var areControlsVisible = true
    private var drawingColor = NSColor.systemYellow
    private var drawingStrokes: [DrawingStroke] = []
    private var drawingRedoStack: [DrawingStroke] = []
    private var activeDrawingStroke: DrawingStroke?
    private let drawingStrokeScreenWidth: CGFloat = 3
    private var textEditor: NSTextField?
    private var editingTextID: UUID?
    private var textEditingUndoSnapshot: BoardProject?
    private var isEditingExistingText = false
    private var isFinishingTextEdit = false
    private var textFormattingHost: NSHostingView<TextFormattingGlassControl>?
    private var textFormattingControlState: TextFormattingControlState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func configure(
        imageCache: ImageCache,
        isDrawingModeEnabled: Bool,
        isTextModeEnabled: Bool,
        areControlsVisible: Bool,
        drawingColor: NSColor,
        onBoardChanged: @escaping (BoardProject) -> Void,
        onAddFiles: @escaping ([URL]) -> Void,
        onToggleChrome: @escaping () -> Void,
        onDrawingModeChanged: @escaping (Bool) -> Void,
        onTextModeChanged: @escaping (Bool) -> Void,
        onCanvasInteraction: @escaping () -> Void
    ) {
        self.imageCache = imageCache
        let didChangeControlVisibility = self.areControlsVisible != areControlsVisible
        self.areControlsVisible = areControlsVisible
        applyDrawingMode(isDrawingModeEnabled, notify: false)
        applyTextMode(isTextModeEnabled, notify: false)
        self.drawingColor = drawingColor.usingColorSpace(.deviceRGB) ?? drawingColor
        self.onBoardChanged = onBoardChanged
        self.onAddFiles = onAddFiles
        self.onToggleChrome = onToggleChrome
        self.onDrawingModeChanged = onDrawingModeChanged
        self.onTextModeChanged = onTextModeChanged
        self.onCanvasInteraction = onCanvasInteraction
        if didChangeControlVisibility {
            needsDisplay = true
        }
    }

    func setBoard(_ nextBoard: BoardProject) {
        let didSwitchBoards = nextBoard.id != board.id
        let wasEmpty = board.items.isEmpty
        let shouldFitAfterLoad = didSwitchBoards || (wasEmpty && !nextBoard.items.isEmpty)

        if didSwitchBoards {
            cancelTextEditing()
            clearDrawingSession()
        } else if editingTextID != nil {
            return
        }

        board = nextBoard
        scale = max(0.02, nextBoard.viewport.scale)
        offset = CGPoint(x: nextBoard.viewport.offsetX, y: nextBoard.viewport.offsetY)
        selectedIDs = selectedIDs.intersection(Set(nextBoard.items.map(\.id)))
        updateTextEditorFrame()

        needsDisplay = true

        if shouldFitAfterLoad {
            DispatchQueue.main.async { [weak self] in
                self?.fitAll()
            }
        }
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
        addNotificationObservers()
        makeTextFormattingHost()
    }

    private func addNotificationObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .imageCanvasFitAll, object: nil, queue: .main) { [weak self] _ in self?.fitAll() })
        observers.append(center.addObserver(forName: .imageCanvasZoomIn, object: nil, queue: .main) { [weak self] _ in self?.zoomIn() })
        observers.append(center.addObserver(forName: .imageCanvasZoomOut, object: nil, queue: .main) { [weak self] _ in self?.zoomOut() })
        observers.append(center.addObserver(forName: .imageCanvasSelectAll, object: nil, queue: .main) { [weak self] _ in self?.selectAll() })
        observers.append(center.addObserver(forName: .imageCanvasRemoveSelected, object: nil, queue: .main) { [weak self] _ in self?.removeSelected() })
        observers.append(center.addObserver(forName: .imageCanvasRotateSelected, object: nil, queue: .main) { [weak self] _ in self?.rotateSelected() })
        observers.append(center.addObserver(forName: .imageCanvasFlipHorizontal, object: nil, queue: .main) { [weak self] _ in self?.flipSelected(horizontal: true) })
        observers.append(center.addObserver(forName: .imageCanvasFlipVertical, object: nil, queue: .main) { [weak self] _ in self?.flipSelected(horizontal: false) })
        observers.append(center.addObserver(forName: .imageCanvasArrangePicasa, object: nil, queue: .main) { [weak self] _ in self?.arrange(.picasa) })
        observers.append(center.addObserver(forName: .imageCanvasArrangePinterest, object: nil, queue: .main) { [weak self] _ in self?.arrange(.pinterest) })
        observers.append(center.addObserver(forName: .imageCanvasUndo, object: nil, queue: .main) { [weak self] _ in self?.performUndo() })
        observers.append(center.addObserver(forName: .imageCanvasRedo, object: nil, queue: .main) { [weak self] _ in self?.performRedo() })
        observers.append(center.addObserver(forName: .imageCanvasRedoDrawing, object: nil, queue: .main) { [weak self] _ in self?.performDrawingRedoShortcut() })
        observers.append(center.addObserver(forName: .imageCanvasClearDrawings, object: nil, queue: .main) { [weak self] _ in self?.clearDrawingSession() })
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        updateTextEditorFrame()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        for item in board.items {
            draw(item)
        }

        drawDrawingStrokes()
        drawSnapGuides()
        drawSelectionOutlines()
        drawMarquee()
        updateTextFormattingControl()
    }

    private func draw(_ item: BoardItem) {
        if item.isText {
            drawText(item)
            return
        }

        let rect = screenRect(for: item.frame.cgRect).integral
        guard rect.intersects(bounds.insetBy(dx: -200, dy: -200)) else { return }

        let targetPixelSize = max(rect.width, rect.height) * max(window?.backingScaleFactor ?? 2, 1)
        guard let image = imageCache?.displayImage(for: item, targetPixelSize: targetPixelSize, isZooming: isZooming) else {
            drawMissingImage(item, in: rect)
            return
        }

        NSGraphicsContext.saveGraphicsState()

        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: CGFloat(item.rotationDegrees))
        transform.scaleX(
            by: item.isFlippedHorizontally ? -1 : 1,
            yBy: item.isFlippedVertically ? -1 : 1
        )
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()

        let drawRect = rotatedImageDrawRect(for: item, in: rect)
        image.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: interpolationQuality(for: drawRect)]
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(_ item: BoardItem) {
        guard item.id != editingTextID else { return }

        let rect = screenRect(for: item.frame.cgRect).integral
        guard rect.intersects(bounds.insetBy(dx: -200, dy: -200)) else { return }

        let font = textFont(for: item, in: rect)
        let text = item.displayedText
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let contentRect = textContentRect(for: rect)

        let textOrigin = CGPoint(
            x: contentRect.minX,
            y: contentRect.midY - textSize.height / 2
        )

        NSGraphicsContext.saveGraphicsState()

        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: CGFloat(item.rotationDegrees))
        transform.scaleX(
            by: item.isFlippedHorizontally ? -1 : 1,
            yBy: item.isFlippedVertically ? -1 : 1
        )
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()

        (text as NSString).draw(
            at: textOrigin,
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private func textFont(for item: BoardItem, text textOverride: String? = nil, in rect: CGRect) -> NSFont {
        let weight: NSFont.Weight = item.isBold ? .bold : .regular
        let resolvedText = textOverride ?? item.displayedText
        let measurementText = resolvedText.isEmpty ? "Text" : resolvedText
        let contentRect = textContentRect(for: rect)

        func makeFont(size: CGFloat) -> NSFont {
            let baseFont = NSFont.systemFont(ofSize: size, weight: weight)
            guard item.isItalic else { return baseFont }

            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(baseFont.fontDescriptor.symbolicTraits.union(.italic))
            return NSFont(descriptor: descriptor, size: size) ?? baseFont
        }

        let referenceFont = makeFont(size: 100)
        let referenceWidth = (measurementText as NSString).size(withAttributes: [.font: referenceFont]).width
        let maximumSize = max(1, contentRect.height * 0.62)
        var fittedSize = min(maximumSize, contentRect.width * 100 / max(referenceWidth, 1))
        var font = makeFont(size: fittedSize)
        let measuredWidth = (measurementText as NSString).size(withAttributes: [.font: font]).width

        if measuredWidth > contentRect.width {
            fittedSize *= contentRect.width / measuredWidth
            font = makeFont(size: max(fittedSize, 1))
        }

        return font
    }

    private func textContentRect(for rect: CGRect) -> CGRect {
        rect.insetBy(dx: min(12, rect.width / 5), dy: 0)
    }

    private func rotatedImageDrawRect(for item: BoardItem, in rect: CGRect) -> CGRect {
        let normalizedRotation = ((item.rotationDegrees % 360) + 360) % 360
        guard normalizedRotation == 90 || normalizedRotation == 270 else {
            return rect
        }

        return CGRect(
            x: rect.midX - rect.height / 2,
            y: rect.midY - rect.width / 2,
            width: rect.height,
            height: rect.width
        )
    }

    private func drawMissingImage(_ item: BoardItem, in rect: CGRect) {
        NSColor(white: 0.16, alpha: 1).setFill()
        NSBezierPath(rect: rect).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 0.72, alpha: 1),
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .paragraphStyle: paragraph
        ]
        NSString(string: item.fileName).draw(in: rect.insetBy(dx: 10, dy: 10), withAttributes: attributes)
    }

    private func drawDrawingStrokes() {
        for stroke in drawingStrokes {
            draw(stroke)
        }

        if let activeDrawingStroke {
            draw(activeDrawingStroke)
        }
    }

    private func draw(_ stroke: DrawingStroke) {
        guard let firstCanvasPoint = stroke.points.first else { return }

        stroke.color.setStroke()
        stroke.color.setFill()

        let strokeWidth = max(stroke.lineWidth * scale, 1.5)
        let firstScreenPoint = screenPoint(from: firstCanvasPoint)

        guard stroke.points.count > 1 else {
            let dotRect = CGRect(
                x: firstScreenPoint.x - strokeWidth / 2,
                y: firstScreenPoint.y - strokeWidth / 2,
                width: strokeWidth,
                height: strokeWidth
            )
            NSBezierPath(ovalIn: dotRect).fill()
            return
        }

        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.move(to: firstScreenPoint)

        for canvasPoint in stroke.points.dropFirst() {
            path.line(to: screenPoint(from: canvasPoint))
        }

        path.stroke()
    }

    private func drawSelectionOutlines() {
        guard !selectedIDs.isEmpty else { return }

        if selectedIDs.count > 1 {
            for item in board.items where selectedIDs.contains(item.id) {
                let rect = screenRect(for: item.frame.cgRect).integral
                NSColor.systemBlue.withAlphaComponent(0.62).setStroke()
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 1
                path.stroke()
            }

            if let groupRect = selectedGroupScreenRect() {
                NSColor.systemBlue.setStroke()
                let path = NSBezierPath(rect: groupRect.integral)
                path.lineWidth = 1
                path.stroke()
                drawResizeHandles(for: groupRect)
            }

            return
        }

        for item in board.items where selectedIDs.contains(item.id) {
            let rect = screenRect(for: item.frame.cgRect).integral
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            path.stroke()

            drawResizeHandles(for: rect)
        }
    }

    private func selectedTextItem() -> BoardItem? {
        guard selectedIDs.count == 1,
              let selectedID = selectedIDs.first,
              let item = board.items.first(where: { $0.id == selectedID }),
              item.isText else {
            return nil
        }

        return item
    }

    private func makeTextFormattingHost() {
        let host = NSHostingView(
            rootView: TextFormattingGlassControl(
                isBold: false,
                isItalic: false,
                onToggleBold: { [weak self] in self?.toggleTextStyle(.bold) },
                onToggleItalic: { [weak self] in self?.toggleTextStyle(.italic) }
            )
        )
        host.isHidden = true
        addSubview(host)
        textFormattingHost = host
    }

    private func updateTextFormattingControl() {
        guard areControlsVisible,
              editingTextID == nil,
              let item = selectedTextItem(),
              let host = textFormattingHost else {
            textFormattingHost?.isHidden = true
            textFormattingControlState = nil
            return
        }

        let nextState = TextFormattingControlState(
            itemID: item.id,
            isBold: item.isBold,
            isItalic: item.isItalic
        )

        if nextState != textFormattingControlState {
            host.rootView = TextFormattingGlassControl(
                isBold: item.isBold,
                isItalic: item.isItalic,
                onToggleBold: { [weak self] in self?.toggleTextStyle(.bold) },
                onToggleItalic: { [weak self] in self?.toggleTextStyle(.italic) }
            )
            textFormattingControlState = nextState
        }

        host.layoutSubtreeIfNeeded()
        let fittingSize = host.fittingSize
        let size = CGSize(width: max(fittingSize.width, 99), height: max(fittingSize.height, 56))
        let itemRect = screenRect(for: item.frame.cgRect)
        let x = min(max(itemRect.midX - size.width / 2, 0), max(bounds.maxX - size.width, 0))
        let y = min(itemRect.maxY + 2, max(bounds.maxY - size.height, 0))
        host.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        host.isHidden = false
    }

    private func drawResizeHandles(for rect: CGRect) {
        NSColor.white.setFill()
        for point in cornerPoints(for: rect) {
            let handleRect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
            NSBezierPath(ovalIn: handleRect).fill()
            NSColor.black.withAlphaComponent(0.42).setStroke()
            let handlePath = NSBezierPath(ovalIn: handleRect)
            handlePath.lineWidth = 1
            handlePath.stroke()
            NSColor.white.setFill()
        }
    }

    private func drawSnapGuides() {
        guard !snapGuides.isEmpty else { return }

        NSColor(white: 0.72, alpha: 0.72).setStroke()
        for guide in snapGuides {
            let path = NSBezierPath()
            path.lineWidth = 1

            switch guide.axis {
            case .vertical:
                let x = screenPoint(from: CGPoint(x: guide.position, y: 0)).x
                path.move(to: CGPoint(x: x, y: 0))
                path.line(to: CGPoint(x: x, y: bounds.height))
            case .horizontal:
                let y = screenPoint(from: CGPoint(x: 0, y: guide.position)).y
                path.move(to: CGPoint(x: 0, y: y))
                path.line(to: CGPoint(x: bounds.width, y: y))
            }

            path.stroke()
        }
    }

    private func drawMarquee() {
        guard let marqueeRect else { return }
        let rect = screenRect(for: marqueeRect).standardized
        NSColor.systemBlue.withAlphaComponent(0.14).setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onCanvasInteraction?()

        let screenPoint = convert(event.locationInWindow, from: nil)
        finishTextEditing()

        if isSpacePressed {
            interaction = .panning(lastScreenPoint: screenPoint)
            return
        }

        let canvasPoint = canvasPoint(from: screenPoint)
        let shiftPressed = event.modifierFlags.contains(.shift)

        if isDrawingModeEnabled {
            beginDrawingStroke(at: canvasPoint)
            return
        }

        if isTextModeEnabled {
            beginTextEditing(at: canvasPoint)
            return
        }

        if selectedIDs.count > 1, let corner = selectedGroupResizeHit(at: screenPoint), let originalBounds = selectedGroupBounds() {
            beginUndo()
            interaction = .resizingGroup(
                corner: corner,
                anchor: resizeAnchor(for: originalBounds, corner: corner),
                originalFrames: originalFramesForSelection(),
                originalBounds: originalBounds,
                aspectRatio: max(originalBounds.width / max(originalBounds.height, 1), 0.001)
            )
            return
        }

        if selectedIDs.count == 1, let resizeHit = selectedItemResizeHit(at: screenPoint) {
            beginUndo()
            let frame = resizeHit.item.frame.cgRect
            interaction = .resizing(
                id: resizeHit.item.id,
                corner: resizeHit.corner,
                anchor: resizeAnchor(for: frame, corner: resizeHit.corner),
                aspectRatio: max(frame.width / max(frame.height, 1), 0.001)
            )
            return
        }

        if let item = item(at: canvasPoint) {
            if event.clickCount == 2, item.isText {
                selectedIDs = [item.id]
                beginTextEditing(item)
                return
            }

            if selectedIDs.count == 1, selectedIDs.contains(item.id), let corner = resizeCornerHit(for: item, at: screenPoint) {
                beginUndo()
                let frame = item.frame.cgRect
                interaction = .resizing(
                    id: item.id,
                    corner: corner,
                    anchor: resizeAnchor(for: frame, corner: corner),
                    aspectRatio: max(frame.width / max(frame.height, 1), 0.001)
                )
                return
            }

            if shiftPressed {
                if selectedIDs.contains(item.id) {
                    selectedIDs.remove(item.id)
                    needsDisplay = true
                    return
                } else {
                    selectedIDs.insert(item.id)
                }
            } else if !selectedIDs.contains(item.id) {
                selectedIDs = [item.id]
            }

            beginUndo()
            interaction = .moving(start: canvasPoint, originalFrames: originalFramesForSelection())
            needsDisplay = true
            return
        }

        if !shiftPressed {
            selectedIDs.removeAll()
        }

        interaction = .marquee(start: canvasPoint)
        marqueeRect = CGRect(origin: canvasPoint, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let screenPoint = convert(event.locationInWindow, from: nil)
        let canvasPoint = canvasPoint(from: screenPoint)

        switch interaction {
        case .none:
            break
        case let .moving(start, originalFrames):
            let rawDX = canvasPoint.x - start.x
            let rawDY = canvasPoint.y - start.y
            let translation = event.modifierFlags.contains(.shift)
                ? snappedTranslation(dx: rawDX, dy: rawDY, originalFrames: originalFrames)
                : (dx: rawDX, dy: rawDY, guides: [])
            snapGuides = translation.guides
            moveSelection(originalFrames: originalFrames, dx: translation.dx, dy: translation.dy)
        case let .resizing(id, corner, anchor, aspectRatio):
            snapGuides = []
            resizeItem(id: id, corner: corner, anchor: anchor, currentPoint: canvasPoint, aspectRatio: aspectRatio)
        case let .resizingGroup(corner, anchor, originalFrames, originalBounds, aspectRatio):
            snapGuides = []
            resizeGroup(corner: corner, anchor: anchor, originalFrames: originalFrames, originalBounds: originalBounds, currentPoint: canvasPoint, aspectRatio: aspectRatio)
        case let .marquee(start):
            let rect = CGRect(
                x: min(start.x, canvasPoint.x),
                y: min(start.y, canvasPoint.y),
                width: abs(canvasPoint.x - start.x),
                height: abs(canvasPoint.y - start.y)
            )
            marqueeRect = rect
            selectedIDs = Set(board.items.filter { $0.frame.cgRect.intersects(rect) }.map(\.id))
            needsDisplay = true
        case let .panning(lastScreenPoint):
            offset.x += screenPoint.x - lastScreenPoint.x
            offset.y += screenPoint.y - lastScreenPoint.y
            interaction = .panning(lastScreenPoint: screenPoint)
            needsDisplay = true
        case .drawing:
            appendDrawingPoint(canvasPoint)
        }
    }

    override func mouseUp(with event: NSEvent) {
        finishInteraction()
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        onCanvasInteraction?()
        interaction = .panning(lastScreenPoint: convert(event.locationInWindow, from: nil))
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDragged(with: event)
            return
        }

        mouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseUp(with: event)
            return
        }

        finishInteraction()
        commitViewport()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            offset.x += event.scrollingDeltaX
            offset.y += event.scrollingDeltaY
            needsDisplay = true
            scheduleViewportCommit()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let factor = event.scrollingDeltaY >= 0 ? 1.08 : 0.92
        zoom(by: factor, around: point, commit: false)
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let factor = max(0.2, 1 + event.magnification)
        zoom(by: factor, around: point, commit: false)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleKeyCommand(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyCommand(event) {
            return
        }

        super.keyDown(with: event)
    }

    private func handleKeyCommand(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if event.keyCode == 49 {
            isSpacePressed = true
            return true
        }

        if flags.contains(.command) {
            switch characters {
            case "1":
                fitAll()
            case "=", "+":
                zoomIn()
            case "-":
                zoomOut()
            case "\\":
                onToggleChrome?()
            case "a":
                selectAll()
            case "z":
                flags.contains(.shift) ? performRedo() : performUndo()
            case "x":
                if isDrawingModeEnabled {
                    redoDrawingStroke()
                } else {
                    return false
                }
            case "r":
                rotateSelected()
            default:
                return false
            }
            return true
        }

        if flags.isEmpty {
            switch characters {
            case "p":
                applyDrawingMode(!isDrawingModeEnabled)
                return true
            case "t":
                applyTextMode(!isTextModeEnabled)
                return true
            case "v":
                applyPointerMode()
                return true
            default:
                break
            }
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            removeSelected()
            return true
        }

        return false
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isSpacePressed = false
            return
        }

        super.keyUp(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []

        let urls = objects.compactMap { object -> URL? in
            if let url = object as? URL { return url }
            if let url = object as? NSURL { return url as URL }
            return nil
        }

        guard !urls.isEmpty else { return false }
        onAddFiles?(urls)
        DispatchQueue.main.async { [weak self] in
            self?.fitAll()
        }
        return true
    }

    private func finishInteraction() {
        switch interaction {
        case .moving, .resizing, .resizingGroup:
            finishUndoAndCommit()
        case .panning:
            commitViewport()
        case .drawing:
            finishDrawingStroke()
        case .marquee, .none:
            break
        }

        interaction = .none
        marqueeRect = nil
        snapGuides = []
        needsDisplay = true
    }

    private func applyDrawingMode(_ isEnabled: Bool, notify: Bool = true) {
        guard isDrawingModeEnabled != isEnabled || (isEnabled && isTextModeEnabled) else { return }

        isDrawingModeEnabled = isEnabled
        if isEnabled {
            if isTextModeEnabled {
                isTextModeEnabled = false
                finishTextEditing()
                if notify {
                    onTextModeChanged?(false)
                }
            }
            selectedIDs.removeAll()
            marqueeRect = nil
            snapGuides = []
        } else {
            activeDrawingStroke = nil
            if case .drawing = interaction {
                interaction = .none
            }
        }

        if notify {
            onDrawingModeChanged?(isEnabled)
        }

        needsDisplay = true
    }

    private func applyTextMode(_ isEnabled: Bool, notify: Bool = true) {
        guard isTextModeEnabled != isEnabled || (isEnabled && isDrawingModeEnabled) else { return }

        isTextModeEnabled = isEnabled
        if isEnabled {
            if isDrawingModeEnabled {
                isDrawingModeEnabled = false
                activeDrawingStroke = nil
                if case .drawing = interaction {
                    interaction = .none
                }
                if notify {
                    onDrawingModeChanged?(false)
                }
            }
            selectedIDs.removeAll()
            marqueeRect = nil
            snapGuides = []
        } else {
            finishTextEditing()
        }

        if notify {
            onTextModeChanged?(isEnabled)
        }

        needsDisplay = true
    }

    private func applyPointerMode() {
        let wasDrawing = isDrawingModeEnabled
        let wasText = isTextModeEnabled
        isDrawingModeEnabled = false
        isTextModeEnabled = false
        activeDrawingStroke = nil
        if case .drawing = interaction {
            interaction = .none
        }
        finishTextEditing()

        if wasDrawing {
            onDrawingModeChanged?(false)
        }
        if wasText {
            onTextModeChanged?(false)
        }

        needsDisplay = true
    }

    private func clearDrawingSession() {
        drawingStrokes.removeAll()
        drawingRedoStack.removeAll()
        activeDrawingStroke = nil
        if case .drawing = interaction {
            interaction = .none
        }
        needsDisplay = true
    }

    private func beginTextEditing(at canvasPoint: CGPoint) {
        finishTextEditing()

        let undoSnapshot = board
        let item = BoardItem(text: "", at: canvasPoint)
        board.items.append(item)
        selectedIDs = [item.id]
        editingTextID = item.id
        textEditingUndoSnapshot = undoSnapshot
        isEditingExistingText = false
        presentTextEditor(initialText: "")
        needsDisplay = true
    }

    private func beginTextEditing(_ item: BoardItem) {
        finishTextEditing()

        selectedIDs = [item.id]
        editingTextID = item.id
        textEditingUndoSnapshot = board
        isEditingExistingText = true
        presentTextEditor(initialText: item.displayedText)
        needsDisplay = true
    }

    private func presentTextEditor(initialText: String) {
        let editor = NSTextField(frame: .zero)
        editor.stringValue = initialText
        editor.isEditable = true
        editor.isSelectable = true
        editor.isBezeled = false
        editor.drawsBackground = false
        editor.textColor = .white
        editor.alignment = .left
        editor.lineBreakMode = .byClipping
        editor.usesSingleLineMode = true
        editor.cell?.isScrollable = false
        editor.cell?.wraps = false
        editor.focusRingType = .none
        editor.delegate = self
        editor.target = self
        editor.action = #selector(submitTextEditor(_:))
        addSubview(editor)
        textEditor = editor
        updateTextEditorFrame()

        DispatchQueue.main.async { [weak self, weak editor] in
            guard let self, let editor, self.textEditor === editor else { return }
            self.window?.makeFirstResponder(editor)
        }
    }

    @objc private func submitTextEditor(_ sender: NSTextField) {
        guard sender === textEditor else { return }
        finishTextEditing()
        window?.makeFirstResponder(self)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let editor = obj.object as? NSTextField, editor === textEditor else { return }
        finishTextEditing()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let editor = obj.object as? NSTextField, editor === textEditor else { return }
        updateTextEditorFrame()
    }

    private func finishTextEditing() {
        guard !isFinishingTextEdit,
              let editor = textEditor,
              let itemID = editingTextID else { return }

        isFinishingTextEdit = true
        defer { isFinishingTextEdit = false }

        let shouldReturnToPointer = !isEditingExistingText && isTextModeEnabled
        let text = editor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.removeFromSuperview()
        textEditor = nil
        editingTextID = nil

        if text.isEmpty {
            board.items.removeAll { $0.id == itemID }
            selectedIDs.remove(itemID)
        } else if let index = board.items.firstIndex(where: { $0.id == itemID }) {
            board.items[index].text = text
            if let undoSnapshot = textEditingUndoSnapshot, undoSnapshot != board {
                pushUndo(undoSnapshot)
                redoStack.removeAll()
                commitBoardChange()
            }
        }

        textEditingUndoSnapshot = nil
        isEditingExistingText = false

        if shouldReturnToPointer {
            isTextModeEnabled = false
            onTextModeChanged?(false)
        }

        needsDisplay = true
    }

    private func cancelTextEditing() {
        guard let itemID = editingTextID else { return }

        textEditor?.removeFromSuperview()
        textEditor = nil
        editingTextID = nil
        textEditingUndoSnapshot = nil
        if !isEditingExistingText {
            board.items.removeAll { $0.id == itemID }
            selectedIDs.remove(itemID)
        }
        isEditingExistingText = false
        needsDisplay = true
    }

    private func updateTextEditorFrame() {
        guard let editor = textEditor,
              let itemID = editingTextID,
              let item = board.items.first(where: { $0.id == itemID }) else { return }

        let rect = screenRect(for: item.frame.cgRect)
        let contentRect = textContentRect(for: rect)
        let font = textFont(for: item, text: editor.stringValue, in: rect)
        let editorHeight = max(font.ascender - font.descender + 8, 18)
        editor.frame = CGRect(
            x: contentRect.minX,
            y: rect.midY - editorHeight / 2,
            width: max(contentRect.width, 24),
            height: editorHeight
        )
        editor.font = font
        editor.needsDisplay = true
    }

    private func toggleTextStyle(_ action: TextStyleAction) {
        guard let item = selectedTextItem() else { return }

        mutateWithUndo {
            guard let index = board.items.firstIndex(where: { $0.id == item.id }) else { return }

            switch action {
            case .bold:
                board.items[index].isBold.toggle()
            case .italic:
                board.items[index].isItalic.toggle()
            }
        }
    }

    private func beginDrawingStroke(at canvasPoint: CGPoint) {
        selectedIDs.removeAll()
        snapGuides = []
        marqueeRect = nil
        drawingRedoStack.removeAll()
        activeDrawingStroke = DrawingStroke(
            color: drawingColor,
            lineWidth: drawingStrokeScreenWidth / max(scale, 0.02),
            points: [canvasPoint]
        )
        interaction = .drawing
        needsDisplay = true
    }

    private func appendDrawingPoint(_ canvasPoint: CGPoint) {
        guard var stroke = activeDrawingStroke else { return }

        if let lastPoint = stroke.points.last {
            let dx = canvasPoint.x - lastPoint.x
            let dy = canvasPoint.y - lastPoint.y
            let minimumDistance = 0.75 / max(scale, 0.02)
            guard hypot(dx, dy) >= minimumDistance else { return }
        }

        stroke.points.append(canvasPoint)
        activeDrawingStroke = stroke
        needsDisplay = true
    }

    private func finishDrawingStroke() {
        guard let stroke = activeDrawingStroke else { return }

        drawingStrokes.append(stroke)
        activeDrawingStroke = nil
        drawingRedoStack.removeAll()
        needsDisplay = true
    }

    private func undoDrawingStroke() {
        if activeDrawingStroke != nil {
            activeDrawingStroke = nil
            interaction = .none
            needsDisplay = true
            return
        }

        guard let stroke = drawingStrokes.popLast() else { return }
        drawingRedoStack.append(stroke)
        needsDisplay = true
    }

    private func redoDrawingStroke() {
        guard let stroke = drawingRedoStack.popLast() else { return }
        drawingStrokes.append(stroke)
        needsDisplay = true
    }

    private func performUndo() {
        isDrawingModeEnabled ? undoDrawingStroke() : undo()
    }

    private func performRedo() {
        isDrawingModeEnabled ? redoDrawingStroke() : redo()
    }

    private func performDrawingRedoShortcut() {
        guard isDrawingModeEnabled else { return }
        redoDrawingStroke()
    }

    private func selectAll() {
        selectedIDs = Set(board.items.map(\.id))
        needsDisplay = true
    }

    private func removeSelected() {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedIDs
        mutateWithUndo {
            board.items.removeAll { ids.contains($0.id) }
            selectedIDs.removeAll()
        }
    }

    private func rotateSelected() {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedIDs

        mutateWithUndo {
            for index in board.items.indices where ids.contains(board.items[index].id) {
                var frame = board.items[index].frame.cgRect
                let center = CGPoint(x: frame.midX, y: frame.midY)
                swap(&frame.size.width, &frame.size.height)
                frame.origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
                board.items[index].frame = CanvasRect(frame)
                board.items[index].rotationDegrees = (board.items[index].rotationDegrees + 90) % 360
            }
        }
    }

    private func flipSelected(horizontal: Bool) {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedIDs

        mutateWithUndo {
            for index in board.items.indices where ids.contains(board.items[index].id) {
                if horizontal {
                    board.items[index].isFlippedHorizontally.toggle()
                } else {
                    board.items[index].isFlippedVertically.toggle()
                }
            }
        }
    }

    private func arrange(_ mode: LayoutMode) {
        let arrangingSelection = !selectedIDs.isEmpty
        let images = board.items.filter { item in
            item.isImage && (!arrangingSelection || selectedIDs.contains(item.id))
        }
        guard !images.isEmpty else { return }

        let originalBounds = LayoutEngine.boundingRect(for: images.map(\.frame.cgRect))
        let arranged: [BoardItem]
        switch mode {
        case .picasa:
            arranged = LayoutEngine.picasaLayout(items: images)
        case .pinterest:
            arranged = LayoutEngine.pinterestLayout(
                items: images,
                availableWidth: max(bounds.width / max(scale, 0.02), 900)
            )
        }

        let arrangedBounds = LayoutEngine.boundingRect(for: arranged.map(\.frame.cgRect))
        let translation = CGPoint(
            x: arrangingSelection ? originalBounds.midX - arrangedBounds.midX : 0,
            y: arrangingSelection ? originalBounds.midY - arrangedBounds.midY : 0
        )
        let arrangedFrames = Dictionary(uniqueKeysWithValues: arranged.map { item in
            let frame = item.frame.cgRect.offsetBy(dx: translation.x, dy: translation.y)
            return (item.id, CanvasRect(frame))
        })

        mutateWithUndo {
            for index in board.items.indices {
                guard let frame = arrangedFrames[board.items[index].id] else { continue }
                board.items[index].frame = frame
            }
            board.layoutMode = mode
        }

        if !arrangingSelection {
            fitAll()
        }
    }

    private func fitAll() {
        guard !bounds.isEmpty else { return }
        guard !board.items.isEmpty else {
            scale = 1
            offset = CGPoint(x: bounds.midX, y: bounds.midY)
            needsDisplay = true
            commitViewport()
            return
        }

        let contentBounds = LayoutEngine.boundingRect(for: board.items.map(\.frame.cgRect))
        let paddedWidth = max(contentBounds.width, 1)
        let paddedHeight = max(contentBounds.height, 1)
        let availableWidth = max(bounds.width - 120, 120)
        let availableHeight = max(bounds.height - 120, 120)
        let nextScale = min(availableWidth / paddedWidth, availableHeight / paddedHeight)

        scale = min(max(nextScale, 0.02), 4)
        offset = CGPoint(
            x: bounds.midX - contentBounds.midX * scale,
            y: bounds.midY - contentBounds.midY * scale
        )
        needsDisplay = true
        commitViewport()
    }

    private func zoomIn() {
        zoom(by: 1.18, around: CGPoint(x: bounds.midX, y: bounds.midY), commit: true)
    }

    private func zoomOut() {
        zoom(by: 0.84, around: CGPoint(x: bounds.midX, y: bounds.midY), commit: true)
    }

    private func zoom(by factor: CGFloat, around screenPoint: CGPoint, commit: Bool) {
        beginZooming()
        let before = canvasPoint(from: screenPoint)
        scale = min(max(scale * factor, 0.02), 8)
        offset = CGPoint(x: screenPoint.x - before.x * scale, y: screenPoint.y - before.y * scale)
        needsDisplay = true

        if commit {
            commitViewport()
        } else {
            scheduleViewportCommit()
        }
    }

    private func beginZooming() {
        isZooming = true
        zoomSettleWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.isZooming = false
            self?.needsDisplay = true
        }
        zoomSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }

    private func interpolationQuality(for rect: CGRect) -> NSImageInterpolation {
        if isZooming {
            return .low
        }

        if max(rect.width, rect.height) < 480 {
            return .medium
        }

        return .high
    }

    private func item(at canvasPoint: CGPoint) -> BoardItem? {
        board.items.reversed().first { $0.frame.cgRect.contains(canvasPoint) }
    }

    private func originalFramesForSelection() -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: board.items
            .filter { selectedIDs.contains($0.id) }
            .map { ($0.id, $0.frame.cgRect) })
    }

    private func moveSelection(originalFrames: [UUID: CGRect], dx: CGFloat, dy: CGFloat) {
        for index in board.items.indices {
            guard let original = originalFrames[board.items[index].id] else { continue }
            board.items[index].frame = CanvasRect(original.offsetBy(dx: dx, dy: dy))
        }
        needsDisplay = true
    }

    private func resizeItem(id: UUID, corner: ResizeCorner, anchor: CGPoint, currentPoint: CGPoint, aspectRatio: CGFloat) {
        guard let index = board.items.firstIndex(where: { $0.id == id }) else { return }

        let frame = resizedRect(corner: corner, anchor: anchor, currentPoint: currentPoint, aspectRatio: aspectRatio, minimumSize: 32)
        board.items[index].frame = CanvasRect(frame)
        needsDisplay = true
    }

    private func resizeGroup(
        corner: ResizeCorner,
        anchor: CGPoint,
        originalFrames: [UUID: CGRect],
        originalBounds: CGRect,
        currentPoint: CGPoint,
        aspectRatio: CGFloat
    ) {
        guard originalBounds.width > 0, originalBounds.height > 0 else { return }

        let nextBounds = resizedRect(
            corner: corner,
            anchor: anchor,
            currentPoint: currentPoint,
            aspectRatio: aspectRatio,
            minimumSize: 64
        )

        let scaleX = nextBounds.width / originalBounds.width
        let scaleY = nextBounds.height / originalBounds.height

        for index in board.items.indices {
            guard let original = originalFrames[board.items[index].id] else { continue }

            let nextFrame = CGRect(
                x: nextBounds.minX + (original.minX - originalBounds.minX) * scaleX,
                y: nextBounds.minY + (original.minY - originalBounds.minY) * scaleY,
                width: original.width * scaleX,
                height: original.height * scaleY
            )
            board.items[index].frame = CanvasRect(nextFrame)
        }

        needsDisplay = true
    }

    private func resizedRect(
        corner: ResizeCorner,
        anchor: CGPoint,
        currentPoint: CGPoint,
        aspectRatio: CGFloat,
        minimumSize: CGFloat
    ) -> CGRect {
        let dx = currentPoint.x - anchor.x
        let dy = currentPoint.y - anchor.y
        var width = abs(dx)
        var height = abs(dy)

        if width / max(aspectRatio, 0.001) > height {
            height = width / max(aspectRatio, 0.001)
        } else {
            width = height * aspectRatio
        }

        width = max(width, minimumSize)
        height = max(height, minimumSize / max(aspectRatio, 0.001))

        switch corner {
        case .topLeft:
            return CGRect(x: anchor.x - width, y: anchor.y - height, width: width, height: height)
        case .topRight:
            return CGRect(x: anchor.x, y: anchor.y - height, width: width, height: height)
        case .bottomLeft:
            return CGRect(x: anchor.x - width, y: anchor.y, width: width, height: height)
        case .bottomRight:
            return CGRect(x: anchor.x, y: anchor.y, width: width, height: height)
        }
    }

    private func resizeCornerHit(for item: BoardItem, at screenPoint: CGPoint) -> ResizeCorner? {
        let rect = screenRect(for: item.frame.cgRect)
        return resizeCornerHit(in: rect, at: screenPoint)
    }

    private func resizeCornerHit(in rect: CGRect, at screenPoint: CGPoint) -> ResizeCorner? {
        let threshold: CGFloat = 24
        let corners: [(ResizeCorner, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY))
        ]

        return corners.first { _, point in
            abs(point.x - screenPoint.x) <= threshold && abs(point.y - screenPoint.y) <= threshold
        }?.0
    }

    private func selectedItemResizeHit(at screenPoint: CGPoint) -> (item: BoardItem, corner: ResizeCorner)? {
        for item in board.items.reversed() where selectedIDs.contains(item.id) {
            if let corner = resizeCornerHit(for: item, at: screenPoint) {
                return (item, corner)
            }
        }

        return nil
    }

    private func selectedGroupResizeHit(at screenPoint: CGPoint) -> ResizeCorner? {
        guard let rect = selectedGroupScreenRect() else { return nil }
        return resizeCornerHit(in: rect, at: screenPoint)
    }

    private func selectedGroupBounds() -> CGRect? {
        let rects = board.items
            .filter { selectedIDs.contains($0.id) }
            .map(\.frame.cgRect)

        guard !rects.isEmpty else { return nil }
        return LayoutEngine.boundingRect(for: rects)
    }

    private func selectedGroupScreenRect() -> CGRect? {
        guard let bounds = selectedGroupBounds() else { return nil }
        return screenRect(for: bounds)
    }

    private func resizeAnchor(for frame: CGRect, corner: ResizeCorner) -> CGPoint {
        switch corner {
        case .topLeft:
            CGPoint(x: frame.maxX, y: frame.maxY)
        case .topRight:
            CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomLeft:
            CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomRight:
            CGPoint(x: frame.minX, y: frame.minY)
        }
    }

    private func snappedTranslation(dx: CGFloat, dy: CGFloat, originalFrames: [UUID: CGRect]) -> (dx: CGFloat, dy: CGFloat, guides: [SnapGuide]) {
        let movingRects = originalFrames.values.map { $0.offsetBy(dx: dx, dy: dy) }
        let movingBounds = LayoutEngine.boundingRect(for: movingRects)
        let fixedRects = board.items
            .filter { originalFrames[$0.id] == nil }
            .map(\.frame.cgRect)
        let threshold = max(4, 10 / max(scale, 0.02))

        var bestDX: CGFloat?
        var bestDY: CGFloat?
        var guides: [SnapGuide] = []

        for fixed in fixedRects {
            for target in [fixed.minX, fixed.maxX] {
                for movingEdge in [movingBounds.minX, movingBounds.maxX] {
                    let candidate = target - movingEdge
                    if abs(candidate) <= threshold,
                       bestDX == nil || abs(candidate) < abs(bestDX ?? 0) {
                        bestDX = candidate
                        guides.removeAll { $0.axis == .vertical }
                        guides.append(SnapGuide(axis: .vertical, position: target))
                    }
                }
            }

            for target in [fixed.minY, fixed.maxY] {
                for movingEdge in [movingBounds.minY, movingBounds.maxY] {
                    let candidate = target - movingEdge
                    if abs(candidate) <= threshold,
                       bestDY == nil || abs(candidate) < abs(bestDY ?? 0) {
                        bestDY = candidate
                        guides.removeAll { $0.axis == .horizontal }
                        guides.append(SnapGuide(axis: .horizontal, position: target))
                    }
                }
            }
        }

        return (dx + (bestDX ?? 0), dy + (bestDY ?? 0), guides)
    }

    private func beginUndo() {
        pendingUndoSnapshot = board
    }

    private func finishUndoAndCommit() {
        if let pendingUndoSnapshot, pendingUndoSnapshot != board {
            pushUndo(pendingUndoSnapshot)
            redoStack.removeAll()
            commitBoardChange()
        }
        pendingUndoSnapshot = nil
    }

    private func mutateWithUndo(_ mutation: () -> Void) {
        let snapshot = board
        mutation()

        guard snapshot != board else { return }
        pushUndo(snapshot)
        redoStack.removeAll()
        commitBoardChange()
        needsDisplay = true
    }

    private func pushUndo(_ snapshot: BoardProject) {
        undoStack.append(snapshot)
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(board)
        board = previous
        selectedIDs = selectedIDs.intersection(Set(board.items.map(\.id)))
        commitBoardChange()
        needsDisplay = true
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        pushUndo(board)
        board = next
        selectedIDs = selectedIDs.intersection(Set(board.items.map(\.id)))
        commitBoardChange()
        needsDisplay = true
    }

    private func commitBoardChange() {
        var next = board
        next.viewport = currentViewport()
        board = next
        onBoardChanged?(next)
    }

    private func commitViewport() {
        viewportCommitWorkItem?.cancel()
        var next = board
        next.viewport = currentViewport()
        board = next
        onBoardChanged?(next)
    }

    private func scheduleViewportCommit() {
        viewportCommitWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.commitViewport()
        }
        viewportCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func currentViewport() -> ViewportState {
        ViewportState(scale: scale, offsetX: offset.x, offsetY: offset.y)
    }

    private func canvasPoint(from screenPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - offset.x) / max(scale, 0.02),
            y: (screenPoint.y - offset.y) / max(scale, 0.02)
        )
    }

    private func screenPoint(from canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * scale + offset.x,
            y: canvasPoint.y * scale + offset.y
        )
    }

    private func screenRect(for canvasRect: CGRect) -> CGRect {
        CGRect(
            x: canvasRect.minX * scale + offset.x,
            y: canvasRect.minY * scale + offset.y,
            width: canvasRect.width * scale,
            height: canvasRect.height * scale
        )
    }

    private func cornerPoints(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
    }
}
