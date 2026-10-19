# eqpop

A macOS menu-bar popup that renders LaTeX or Markdown (through pdfmd) to a cropped vector PDF. Swift, SwiftPM, no
Xcode: `./build.sh` makes `build/eqpop.app`. The README lists the features; this file is only process.

This repository is public: no personal details (absolute home paths, names) in code, README or CHANGELOG; use `~/`.

## Process

- Commit the change, its `CHANGELOG.md` entry and the `eqpopVersion` bump together (see the changelog's header).
- Test headless first: `swift build -c release && .build/release/eqpop --selftest`, and `eqpop --render` with
  `env -i PATH=/usr/bin:/bin` to see what a Finder-launched app sees (no TeX on its PATH).
- **Do not launch the window while the author may be typing**: a launched app takes the keyboard focus and the
  author's keystrokes land in it. `open build/eqpop.app` (no `--show`) starts it without opening the window.
- Keystrokes cannot be sent to the app from here (no Accessibility permission): the hotkey, ⌘↩, drag-out and the
  save dialog are checked by the author.
- Edits made with `defaults write` to the app's settings need `-string` for text that starts with a backslash.
