# ImageCanvas

ImageCanvas is a native macOS visual reference board for arranging locally stored images on a canvas.

![ImageCanvas preview](assets/imagecanvas-preview.png)

## Features

- Import images from files or folders without modifying the originals.
- Arrange images with Equalized Tiled Grid, resolution-informed Native Tiled Grid, or Cascading Grid.
- Hold Option while hovering over an image to reveal its complete filename.
- Rotate, flip, or reveal selected images in Finder from the context or Selection menu.
- Pan, zoom, select, move, resize, rotate, and flip board items.
- Add persistent text objects with Bold and Italic styling and session-only pen drawings.
- Create clean board snapshots at a configurable resolution. Snapshots are copied to the clipboard and saved to Pictures by default.
- Check for the latest stable release manually from the ImageCanvas menu, with automatic replacement available for writable installations.
- Supported image formats: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, and `.heif`.

## Requirements

- macOS 14 or later.
- To build from source: Xcode 27 beta 3 or later with the macOS SDK.

Because releases are neither notarized nor independently signed, macOS may block the first launch. Verify that the archive and SHA-256 digest came from this repository's release page, then use System Settings > Privacy & Security > Open Anyway. Building from source remains the preferred path when the code must be inspected before running it.

The built-in updater checks only the latest stable GitHub Release when requested. It verifies GitHub's published SHA-256 digest and the downloaded app's identity, version, structure, and ad-hoc signature before replacing a writable copy. GitHub supplies both the archive and its digest; this is transport and integrity validation, not independent publisher authentication. Open GitHub remains available for manual installation.

## Some Useful Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘+\ | Show or hide controls |
| P | Paint tool |
| V | Pointer tool |
| T | Text tool |
| ⌘+R | Rotate clockwise |
| ⇧+⌘+R | Rotate counterclockwise |
| ⌘+F | Flip horizontally |
| ⇧+⌘+F | Flip vertically |
| ⌘+1 | Fit the board in the window |

## Usage example

ImageCanvas grew out of a recurring problem: previewing hundreds of mixed files in Downloads while trying to find one particular image. It can open a folder, ignore everything that is not an image, and arrange the results as a visual board—closer to working in Figma or PureRef than browsing a file list. The same lightweight organizing tools are useful when a group of references needs to be prepared quickly for a presentation or screen-sharing call.

## Development Notes

- Images are referenced from their existing locations; ImageCanvas does not copy or modify source files.
- Board layout and text objects are persisted locally in Application Support.
- Pen drawings are intentionally session-only and are never persisted.

## License

ImageCanvas is released under the [MIT License](LICENSE).
