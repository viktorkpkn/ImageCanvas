# ImageCanvas

ImageCanvas is a native macOS visual reference board for arranging locally stored images on a canvas.

## Features

- Import images from files or folders without modifying the originals.
- Arrange images with Tiled grid or Cascading grid layouts.
- Pan, zoom, select, move, resize, rotate, and flip board items.
- Add persistent text objects with Bold and Italic styling.
- Add transient, session-only pen drawings.

## Requirements

- macOS 14 or later.
- If you want to build yourself: a current Xcode installation with the macOS SDK.

## Build From Source

```sh
git clone <repository-url>
cd <repository-directory>
swift build
swift run ImageCanvas
```

To work in Xcode, open `ImageCanvas.xcodeproj` and run the `ImageCanvas` scheme.

## Create An App Bundle

```sh
./Scripts/package_app.sh release
open dist/ImageCanvas.app
```

The packaging script compiles the app and bundles `TestIcon.icon`. The resulting app is ad-hoc signed for local use only. It is not Developer ID-signed or notarized.

## Unsigned Release Archives

```sh
./Scripts/create_release.sh
```

The script produces a versioned ZIP and SHA-256 checksum in `release-assets/`. Upload those files to a GitHub Release. They are intentionally ignored by Git.

Because unsigned releases are not notarized, macOS may block the first launch. Verify that the archive came from the official release page, then use System Settings > Privacy & Security > Open Anyway. Building from source is the preferred path for users who need to inspect the code before running it.

## Development Notes

- Images are referenced from their existing locations; ImageCanvas does not copy or modify source files.
- Board layout and text objects are persisted locally in Application Support.
- Pen drawings are intentionally session-only and are never persisted.

## License

ImageCanvas is released under the [MIT License](LICENSE).
