# ImageCanvas

ImageCanvas is a native macOS visual reference board for arranging locally stored images on a canvas.

![ImageCanvas preview](assets/imagecanvas-preview.png)

## Features

- Import images from files or folders without modifying the originals.
- Arrange images with Tiled grid or Cascading grid layouts.
- Pan, zoom, select, move, resize, rotate, and flip board items.
- Add persistent text objects with Bold and Italic styling.
- Add transient, session-only pen drawings.

## Requirements

- macOS 14 or later.
- If you want to build yourself: a current Xcode installation with the macOS SDK.

Because unsigned releases are not notarized, macOS may block the first launch. Verify that the archive came from the this release page, then use System Settings > Privacy & Security > Open Anyway. Building from source is the preferred path for users who need to inspect the code before running it.

## Development Notes

- Images are referenced from their existing locations; ImageCanvas does not copy or modify source files.
- Board layout and text objects are persisted locally in Application Support.
- Pen drawings are intentionally session-only and are never persisted.

## License

ImageCanvas is released under the [MIT License](LICENSE).
