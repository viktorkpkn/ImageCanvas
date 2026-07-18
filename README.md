# ImageCanvas

ImageCanvas is a native macOS visual reference board for arranging locally stored images on a canvas.

![ImageCanvas preview](assets/imagecanvas-preview.png)

## Features

- Import images from files or folders without modifying the originals.
- Arrange images with Equalized Tiled Grid, resolution-informed Native Tiled Grid, or equalized Cascading Grid.
- Pan, zoom, select, move, resize, rotate, and flip board items.
- Add persistent text objects with Bold and Italic styling.
- Add transient, session-only pen drawings.
- Copy clean board snapshots and save them to Pictures at a configurable resolution.

## Requirements

- macOS 14 or later.
- If you want to build yourself: Xcode 27 beta 3 or later with the macOS SDK.

Because unsigned releases are not notarized, macOS may block the first launch. Verify that the archive came from the this release page, then use System Settings > Privacy & Security > Open Anyway. Building from source is the preferred path for users who need to inspect the code before running it.

## Usage example

I was constantly facing an issue with previewing a large number of images, primarily in the Downloads folder, and spent a lot of time finding a specific image among hundreds of others. This tool allows me to select a folder containing any mix of files and preview only the images inside it in a way I used to organize them in Figma / PureRef. In addition to that it has simple organizing functions for when, say, you would want to share your screen on a Zoom call and quickly show something.  

## Development Notes

- Images are referenced from their existing locations; ImageCanvas does not copy or modify source files.
- Board layout and text objects are persisted locally in Application Support.
- Pen drawings are intentionally session-only and are never persisted.

## License

ImageCanvas is released under the [MIT License](LICENSE).
