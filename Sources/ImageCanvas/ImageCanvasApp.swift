import SwiftUI

@main
struct ImageCanvasApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Board") {
                    post(.imageCanvasNewBoard)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Add Images...") {
                    post(.imageCanvasAddImages)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Open Folder...") {
                    post(.imageCanvasOpenFolder)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Canvas") {
                Button("Fit All") {
                    post(.imageCanvasFitAll)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Zoom In") {
                    post(.imageCanvasZoomIn)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    post(.imageCanvasZoomOut)
                }
                .keyboardShortcut("-", modifiers: .command)

                Divider()

                Button("Show or Hide Controls") {
                    post(.imageCanvasToggleChrome)
                }
                .keyboardShortcut("\\", modifiers: .command)
            }

            CommandMenu("Tools") {
                Button("Text") {
                    post(.imageCanvasToggleTextMode)
                }
                .keyboardShortcut("t", modifiers: [])

                Button("Paint") {
                    post(.imageCanvasToggleDrawingMode)
                }
                .keyboardShortcut("p", modifiers: [])

                Button("Pointer") {
                    post(.imageCanvasDisableDrawingMode)
                }
                .keyboardShortcut("v", modifiers: [])

                Button("Redo Drawing") {
                    post(.imageCanvasRedoDrawing)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Clear Drawings") {
                    post(.imageCanvasClearDrawings)
                }
            }

            CommandMenu("Arrange") {
                Button("Tiled grid") {
                    post(.imageCanvasArrangePicasa)
                }

                Button("Cascading grid") {
                    post(.imageCanvasArrangePinterest)
                }
            }

            CommandMenu("Selection") {
                Button("Select All") {
                    post(.imageCanvasSelectAll)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Remove From Board") {
                    post(.imageCanvasRemoveSelected)
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("Rotate 90 Degrees") {
                    post(.imageCanvasRotateSelected)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Flip Horizontal") {
                    post(.imageCanvasFlipHorizontal)
                }

                Button("Flip Vertical") {
                    post(.imageCanvasFlipVertical)
                }

                Divider()

                Button("Undo") {
                    post(.imageCanvasUndo)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    post(.imageCanvasRedo)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
