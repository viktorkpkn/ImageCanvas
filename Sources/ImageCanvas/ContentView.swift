import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = BoardStore()
    @State private var isChromeVisible = true
    @State private var isProjectMenuPresented = false
    @State private var isDrawingModeEnabled = false
    @State private var isTextModeEnabled = false
    @State private var drawingColor = Color.yellow
    @State private var isDrawingColorPickerPresented = false
    @StateObject private var drawingColorPicker = DrawingColorPickerModel(color: .yellow)

    var body: some View {
        ZStack {
            CanvasViewRepresentable(
                board: store.board,
                imageCache: store.imageCache,
                isDrawingModeEnabled: isDrawingModeEnabled,
                isTextModeEnabled: isTextModeEnabled,
                areControlsVisible: isChromeVisible,
                drawingColor: NSColor(drawingColor),
                onBoardChanged: store.replaceBoard,
                onAddFiles: store.addFiles,
                onToggleChrome: toggleChrome,
                onDrawingModeChanged: setDrawingMode,
                onTextModeChanged: setTextMode,
                onCanvasInteraction: {
                    isDrawingColorPickerPresented = false
                    isProjectMenuPresented = false
                }
            )
            .ignoresSafeArea()

            if isChromeVisible {
                controlsOverlayContent
                    .transition(.opacity)
            }

            WindowChromeConfigurator()
                .frame(width: 0, height: 0)
        }
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .all)
        .frame(minWidth: 900, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: .imageCanvasAddImages)) { _ in
            addImages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCanvasOpenFolder)) { _ in
            openFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCanvasNewBoard)) { _ in
            store.newBoard()
            post(.imageCanvasFitAll)
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCanvasToggleChrome)) { _ in
            toggleChrome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCanvasToggleDrawingMode)) { _ in
            setDrawingMode(!isDrawingModeEnabled)
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCanvasDisableDrawingMode)) { _ in
            setPointerMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCanvasToggleTextMode)) { _ in
            setTextMode(!isTextModeEnabled)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.scanCurrentFolderForUpdates()
        }
        .onChange(of: drawingColorPicker.hue) { _, _ in syncDrawingColor() }
        .onChange(of: drawingColorPicker.saturation) { _, _ in syncDrawingColor() }
        .onChange(of: drawingColorPicker.brightness) { _, _ in syncDrawingColor() }
        .onChange(of: drawingColorPicker.opacity) { _, _ in syncDrawingColor() }
    }

    private var controlsOverlayContent: some View {
        ZStack(alignment: .topTrailing) {
            chrome
                .padding(.top, 18)
                .padding(.trailing, 16)

            toolRail
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if !store.pendingFolderItems.isEmpty {
                updateCanvasButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 18)
                    .zIndex(1)
            }

            if isDrawingColorPickerPresented {
                DrawingColorPickerView(model: drawingColorPicker)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 74)
                    .zIndex(1)
            }

            if isProjectMenuPresented {
                projectFloatingMenu
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 72)
                    .padding(.trailing, 16)
                    .zIndex(2)
            }
        }
    }

    private var chrome: some View {
        HStack(spacing: 10) {
            addImagesButton
            projectMenu
        }
    }

    @ViewBuilder
    private var updateCanvasButton: some View {
        if #available(macOS 26.0, *) {
            Button(action: applyFolderUpdate) {
                glassChromeLabel(systemImage: "arrow.triangle.2.circlepath", title: "Update Canvas")
            }
            .buttonStyle(.plain)
        } else {
            Button(action: applyFolderUpdate) {
                fallbackChromeLabel(systemImage: "arrow.triangle.2.circlepath", title: "Update Canvas")
            }
            .buttonStyle(.plain)
        }
    }

    private var toolRail: some View {
        VStack(spacing: 10) {
            Button {
                setTextMode(true)
            } label: {
                drawingToolLabel(
                    systemImage: "textformat",
                    filledSystemImage: nil,
                    iconColor: isTextModeEnabled ? .accentColor : .white,
                    isActive: isTextModeEnabled,
                    accessibilityLabel: "Text"
                )
            }
            .buttonStyle(.plain)
            .help("Text (T)")

            Button {
                setDrawingMode(true)
                openDrawingColorPicker()
            } label: {
                drawingToolLabel(
                    systemImage: "paintpalette",
                    filledSystemImage: "paintpalette.fill",
                    iconColor: drawingColor,
                    isActive: isDrawingModeEnabled,
                    accessibilityLabel: "Drawing Color"
                )
            }
            .buttonStyle(.plain)
            .help("Paint (P)")
            .contextMenu {
                Button("Clear Drawings") {
                    post(.imageCanvasClearDrawings)
                }
            }

            Button {
                setPointerMode()
            } label: {
                drawingToolLabel(
                    systemImage: "cursorarrow",
                    filledSystemImage: nil,
                    iconColor: !isDrawingModeEnabled && !isTextModeEnabled ? .accentColor : .white,
                    isActive: !isDrawingModeEnabled && !isTextModeEnabled,
                    accessibilityLabel: "Pointer"
                )
            }
            .buttonStyle(.plain)
            .help("Pointer (V)")
        }
    }

    @ViewBuilder
    private var addImagesButton: some View {
        if #available(macOS 26.0, *) {
            Button {
                addImages()
            } label: {
                glassChromeLabel(systemImage: "plus", title: "Add Images")
            }
            .buttonStyle(.plain)
        } else {
            Button {
                addImages()
            } label: {
                fallbackChromeLabel(systemImage: "plus", title: "Add Images")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var projectMenu: some View {
        if #available(macOS 26.0, *) {
            Button {
                isDrawingColorPickerPresented = false
                isProjectMenuPresented.toggle()
            } label: {
                glassIconChromeLabel(systemImage: "folder")
            }
            .buttonStyle(.plain)
        } else {
            Button {
                isDrawingColorPickerPresented = false
                isProjectMenuPresented.toggle()
            } label: {
                fallbackIconChromeLabel(systemImage: "folder")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var projectFloatingMenu: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        if #available(macOS 26.0, *) {
            projectFloatingMenuRows
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.18), lineWidth: 1)
                }
        } else {
            projectFloatingMenuRows
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
    }

    private var projectFloatingMenuRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            projectMenuButton("New Board") {
                store.newBoard()
                post(.imageCanvasFitAll)
            }

            projectMenuButton("Open Folder...") {
                openFolder()
            }

            if !store.recents.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Recent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)

                ForEach(store.recents) { recent in
                    projectMenuButton(recent.name) {
                        store.openRecent(recent)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                projectMenuButton("Clear Recent") {
                    store.clearRecents()
                }
            }
        }
        .padding(10)
        .frame(width: 240)
    }

    private func projectMenuButton(_ title: String, action: @escaping () -> Void) -> some View {
        ProjectFloatingMenuRow(title: title) {
            isProjectMenuPresented = false
            action()
        }
    }

    private func chromeLabel(systemImage: String, title: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 13, weight: .medium))
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
    }

    private func iconChromeLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
    }

    @ViewBuilder
    private func drawingToolLabel(
        systemImage: String,
        filledSystemImage: String?,
        iconColor: Color,
        isActive: Bool,
        accessibilityLabel: String
    ) -> some View {
        ZStack {
            drawingToolGlassSurface()

            if isActive {
                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 42, height: 42)
            }

            drawingToolIcon(
                systemImage: systemImage,
                filledSystemImage: filledSystemImage,
                iconColor: iconColor,
                accessibilityLabel: accessibilityLabel
            )
        }
        .frame(width: 42, height: 42)
        .shadow(color: .black.opacity(isActive ? 0.22 : 0.28), radius: isActive ? 12 : 18, y: isActive ? 6 : 8)
        .contentShape(Circle())
        .accessibilityValue(isActive ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private func drawingToolGlassSurface() -> some View {
        if #available(macOS 26.0, *) {
            Circle()
                .fill(.white.opacity(0.001))
                .frame(width: 42, height: 42)
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
        } else {
            Circle()
                .fill(.clear)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private func drawingToolIcon(
        systemImage: String,
        filledSystemImage: String?,
        iconColor: Color,
        accessibilityLabel: String
    ) -> some View {
        ZStack {
            if let filledSystemImage {
                Image(systemName: filledSystemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityLabel(accessibilityLabel)
    }

    @available(macOS 26.0, *)
    private func glassChromeLabel(systemImage: String, title: String) -> some View {
        chromeLabel(systemImage: systemImage, title: title)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .contentShape(Capsule())
    }

    @available(macOS 26.0, *)
    private func glassIconChromeLabel(systemImage: String) -> some View {
        iconChromeLabel(systemImage: systemImage)
            .glassEffect(.regular.interactive(), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .contentShape(Circle())
            .accessibilityLabel("Project")
    }

    private func fallbackChromeLabel(systemImage: String, title: String) -> some View {
        chromeLabel(systemImage: systemImage, title: title)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    private func fallbackIconChromeLabel(systemImage: String) -> some View {
        iconChromeLabel(systemImage: systemImage)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .accessibilityLabel("Project")
    }

    private func addImages() {
        store.addImagesUsingPanel()
        post(.imageCanvasFitAll)
    }

    private func openFolder() {
        store.openFolderUsingPanel()
    }

    private func applyFolderUpdate() {
        let items = store.pendingFolderItems
        guard !items.isEmpty else { return }

        setPointerMode()
        NotificationCenter.default.post(name: .imageCanvasApplyFolderUpdate, object: items)
    }

    private func toggleChrome() {
        let nextVisibility = !isChromeVisible
        withAnimation(.easeOut(duration: 0.16)) {
            isChromeVisible = nextVisibility
        }
        if !nextVisibility {
            isDrawingColorPickerPresented = false
            isProjectMenuPresented = false
        }
    }

    private func setDrawingMode(_ isEnabled: Bool) {
        withAnimation(.easeOut(duration: 0.16)) {
            isDrawingModeEnabled = isEnabled
            if isEnabled {
                isTextModeEnabled = false
                isProjectMenuPresented = false
            }
            if !isEnabled {
                isDrawingColorPickerPresented = false
            }
        }
    }

    private func setTextMode(_ isEnabled: Bool) {
        withAnimation(.easeOut(duration: 0.16)) {
            isTextModeEnabled = isEnabled
            if isEnabled {
                isDrawingModeEnabled = false
                isDrawingColorPickerPresented = false
                isProjectMenuPresented = false
            }
        }
    }

    private func setPointerMode() {
        withAnimation(.easeOut(duration: 0.16)) {
            isDrawingModeEnabled = false
            isTextModeEnabled = false
            isDrawingColorPickerPresented = false
            isProjectMenuPresented = false
        }
    }

    private func openDrawingColorPicker() {
        drawingColorPicker.setColor(NSColor(drawingColor))
        withAnimation(.easeOut(duration: 0.16)) {
            isProjectMenuPresented = false
            isDrawingColorPickerPresented = true
        }
    }

    private func syncDrawingColor() {
        drawingColor = Color(nsColor: drawingColorPicker.color)
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

private struct ProjectFloatingMenuRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(isHovered ? 0.14 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovered
            }
        }
    }
}

private enum DrawingColorPickerMetrics {
    static let panelSize = CGSize(width: 238, height: 333)
    static let cornerRadius: CGFloat = 22
    static let wheelSize: CGFloat = 193
    static let trackWidth: CGFloat = 193
    static let trackHeight: CGFloat = 18
    static let wheelToTrackGap: CGFloat = 28
    static let trackGap: CGFloat = 14
    static let knobSize: CGFloat = 17
    static let wheelIndicatorSize: CGFloat = 14
}

final class DrawingColorPickerModel: ObservableObject {
    @Published var hue: CGFloat
    @Published var saturation: CGFloat
    @Published var brightness: CGFloat
    @Published var opacity: CGFloat

    init(color: NSColor) {
        let components = Self.components(for: color)
        hue = components.hue
        saturation = components.saturation
        brightness = components.brightness
        opacity = components.opacity
    }

    func setColor(_ color: NSColor) {
        let components = Self.components(for: color)
        hue = components.hue
        saturation = components.saturation
        brightness = components.brightness
        opacity = components.opacity
    }

    var color: NSColor {
        NSColor(
            deviceHue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: opacity
        )
    }

    private static func components(for color: NSColor) -> (
        hue: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat,
        opacity: CGFloat
    ) {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? .yellow
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 1
        var opacity: CGFloat = 1
        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)

        return (hue, saturation, brightness, opacity)
    }

    var opaqueColor: NSColor {
        NSColor(deviceHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

}

struct DrawingColorPickerView: View {
    @ObservedObject var model: DrawingColorPickerModel

    private let shape = RoundedRectangle(
        cornerRadius: DrawingColorPickerMetrics.cornerRadius,
        style: .continuous
    )

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            pickerContent
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.18), lineWidth: 1)
                }
        } else {
            pickerContent
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
    }

    private var pickerContent: some View {
        VStack(spacing: 0) {
            DrawingHueSaturationWheel(model: model)
                .frame(
                    width: DrawingColorPickerMetrics.wheelSize,
                    height: DrawingColorPickerMetrics.wheelSize
                )
                .padding(.bottom, DrawingColorPickerMetrics.wheelToTrackGap)

            DrawingColorTrack(
                value: 1 - model.brightness,
                onChange: { model.brightness = 1 - $0 }
            ) {
                LinearGradient(
                    colors: [Color(nsColor: model.opaqueColor), .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .frame(
                width: DrawingColorPickerMetrics.trackWidth,
                height: DrawingColorPickerMetrics.trackHeight
            )
            .padding(.bottom, DrawingColorPickerMetrics.trackGap)
            .accessibilityLabel("Luminance")

            DrawingColorTrack(
                value: model.opacity,
                onChange: { model.opacity = $0 }
            ) {
                ZStack {
                    DrawingOpacityCheckerboard()
                    LinearGradient(
                        colors: [
                            Color(nsColor: model.opaqueColor).opacity(0),
                            Color(nsColor: model.opaqueColor)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .frame(
                width: DrawingColorPickerMetrics.trackWidth,
                height: DrawingColorPickerMetrics.trackHeight
            )
            .accessibilityLabel("Opacity")
        }
        .frame(
            width: DrawingColorPickerMetrics.panelSize.width,
            height: DrawingColorPickerMetrics.panelSize.height
        )
    }
}

struct DrawingHueSaturationWheel: View {
    @ObservedObject var model: DrawingColorPickerModel

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            let angle = model.hue * 2 * .pi
            let indicatorRadius = model.saturation * radius
            let indicatorPosition = CGPoint(
                x: radius + cos(angle) * indicatorRadius,
                y: radius + sin(angle) * indicatorRadius
            )

            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    ))
                    .overlay {
                        Circle()
                            .fill(RadialGradient(
                                colors: [.white, .white.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: radius
                            ))
                    }
                    .overlay {
                        Circle()
                            .fill(.black.opacity(1 - model.brightness))
                    }
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    }

                Circle()
                    .fill(.clear)
                    .frame(
                        width: DrawingColorPickerMetrics.wheelIndicatorSize,
                        height: DrawingColorPickerMetrics.wheelIndicatorSize
                    )
                    .overlay {
                        Circle().stroke(.white, lineWidth: 2)
                    }
                    .overlay {
                        Circle().stroke(.black.opacity(0.5), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .position(indicatorPosition)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let vector = CGVector(dx: value.location.x - radius, dy: value.location.y - radius)
                let distance = min(hypot(vector.dx, vector.dy), radius)
                var angle = atan2(vector.dy, vector.dx) / (2 * .pi)
                if angle < 0 { angle += 1 }
                model.hue = angle
                model.saturation = distance / radius
            })
            .accessibilityLabel("Hue and saturation")
        }
    }
}

struct DrawingColorTrack<Track: View>: View {
    let value: CGFloat
    let onChange: (CGFloat) -> Void
    @ViewBuilder let track: () -> Track

    private let knobSize = DrawingColorPickerMetrics.knobSize

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knobSize, 1)
            let clampedValue = min(max(value, 0), 1)

            ZStack(alignment: .leading) {
                track()
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(.white.opacity(0.24), lineWidth: 1)
                    }

                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Circle().stroke(.black.opacity(0.45), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: clampedValue * travel)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(max((drag.location.x - knobSize / 2) / travel, 0), 1))
            })
        }
        .frame(height: DrawingColorPickerMetrics.trackHeight)
    }
}

struct DrawingOpacityCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 6
            let columns = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))

            for row in 0..<rows {
                for column in 0..<columns {
                    let color: Color = (row + column).isMultiple(of: 2)
                        ? .white.opacity(0.85)
                        : .gray.opacity(0.45)
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * cellSize,
                            y: CGFloat(row) * cellSize,
                            width: cellSize,
                            height: cellSize
                        )),
                        with: .color(color)
                    )
                }
            }
        }
    }
}
