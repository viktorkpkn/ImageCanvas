# ImageCanvas

ImageCanvas is a native macOS visual reference board for arranging locally stored images on a canvas.

![ImageCanvas preview](assets/imagecanvas-preview.png)

## Features

- Import images from files or folders without modifying the originals.
- Three modes of arrangements: Equalized Tiled Grid and Cascading Grid (Collage and Pinterest-Style Columns), and Native grid that retains resolution of the images.
- Pan, zoom, select, move, resize, rotate, and flip board items.
- Add persistent text objects with Bold and Italic styling and session-only pen drawings.
- Board snapshots with configurable resolution. Auto-copied to clipboard and savied to Pictures (by default).
- Supported image formats: ```.jpg``` ```.jpeg``` ```.png``` ```.gif``` ```.webp``` ```.heic``` ```.heif```

## Requirements

- macOS 14 or later.
- If you want to build yourself: Xcode 27 beta 3 or later with the macOS SDK.

Because unsigned releases are not notarized, macOS may block the first launch. Verify that the archive came from the this release page, then use System Settings > Privacy & Security > Open Anyway. Building from source is the preferred path for users who need to inspect the code before running it.

## Some Useful Shortcuts

⌘+\ — hide UI | P — Drawing Tool | V — Move Tool | T — Type Tool

## Usage example

I was constantly facing an issue with previewing a large number of images, primarily in the Downloads folder, and spent a lot of time finding a specific image among hundreds of others. This tool allows me to select a folder containing any mix of files and preview only the images inside it in a way I used to organize them in Figma / PureRef. In addition to that it has simple organizing functions for when, say, you would want to share your screen on a Zoom call and quickly show something.  

## Development Notes

- Images are referenced from their existing locations; ImageCanvas does not copy or modify source files.
- Board layout and text objects are persisted locally in Application Support.
- Pen drawings are intentionally session-only and are never persisted.

## License

ImageCanvas is released under the [MIT License](LICENSE).
