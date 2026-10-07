# Moon

**A native PDF app for Apple Silicon Macs.** Read, rearrange and add text to PDFs in a dark, focused interface.

> **Status: version 0.2, in active development.** The interface is currently in Italian.

## What it does today

- **Open** PDFs with ⌘O, by dragging them into the window, or with "Open With" from the Finder
- **Browse** with page thumbnails, free zoom, fit to window (⌘0) and actual size (⌘1)
- **Three layouts:** continuous, single page, two pages side by side
- **Organize pages:** rotate, delete and reorder, on one page or a multiple selection
- **Add pages** from other PDFs, or **combine** several PDFs into a new one
- **Extract** the selected pages into a separate PDF
- **Add text:** click to place a text box, then set its words, size and color; drag to move it
- **Undo and redo** for every change
- **Safe saving:** the file is written aside, checked, and only then put in place of the original

## Coming

- Editing the text already in a PDF
- Comments: highlighter, notes, drawing, shapes
- Filling in forms
- Signatures
- True redaction, which removes content instead of covering it
- Password protection

The plan is to build these on [PrintCraft](https://github.com/storytold/printcraft), an open-source PDF engine.
Tools that aren't ready yet appear dimmed in the app.

## Download

Get `Moon-<version>.zip` from the [Releases](../../releases) page, unzip it and drag Moon to Applications.

Moon isn't signed with a paid Apple developer certificate, so macOS blocks it the first time you open it.
To allow it: System Settings › Privacy & Security › scroll down › "Open Anyway". You only need to do this once.

**Requirements:** a Mac with Apple Silicon, macOS 15 or later. Developed and tested on macOS 27.

## Build from source

You need Xcode. Open `Moon.xcodeproj` and press ▶, or double-click `compila.command`.
To make the zip for distribution, double-click `rilascia.command`.

## License

MIT. See [LICENSE](LICENSE).
