# Changelog

All notable changes are documented in this file.

## 0.5.0 - 2026-07-19

- Added an Option-hover filename capsule that floats below the image and remains readable at every canvas zoom level.
- Added selection-aware image context commands for clockwise and counterclockwise rotation, horizontal and vertical flipping, and Reveal in Finder, with matching Selection-menu shortcuts and undo support.
- Added a manual latest-stable-release check under the ImageCanvas menu, including GitHub-published SHA-256 validation, app identity and version checks, writable-app replacement and relaunch, rollback on failure, and a manual GitHub fallback.
- Preserved macOS 14 support and updated the release to version 0.5.0 build 4.

## 0.4.1 - 2026-07-18

- Restored the original compact Picasa arrangement as Equalized Tiled Grid.
- Added a separate resolution-informed Native Tiled Grid with compact justified rows.
- Made Cascading Grid equalized-only and independent of window zoom, and flattened Arrange into three direct commands.

## 0.4.0 - 2026-07-18

- Added clean board snapshots with whole-board padding or current-view capture, configurable resolution, clipboard copy, Pictures saving, and a File menu export route.
- Added confirmation before attempting snapshot dimensions above 8K.
- Added independent Equalize Images and native Scale by Resolution choices for Tiled and Cascading arrangements.
- Added the new Icon Composer app icon and updated the project for Xcode 27 beta 3 while retaining macOS 14 support.

## 0.3.6 - 2026-07-12

- Fixed recent-folder reopening and refreshed project menu behavior.
- Added selection-aware Tiled grid and Cascading grid arrangements.
- Preserved extreme image aspect ratios in Cascading grid layouts.
- Added persistent SF text editing and session-only drawing tools with Liquid Glass controls.
