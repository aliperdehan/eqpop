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
- `./build.sh --install` builds, quits the running app, copies it to `~/Applications` and starts it (no window). Run it
  after a change the author should try; the running copy is otherwise the old binary.
- Edits made with `defaults write` to the app's settings need `-string` for text that starts with a backslash.

## Screenshots and releases

`EQPOP_HOME=build/shot-home .build/release/eqpop --screenshot docs/screenshot.png` draws the window off screen:
nothing appears, no keystroke can land in it, and it runs on scratch settings (suite `eqpop-screenshot`) with the
default preamble, so none of the author's own preamble or text is in the picture. `EQPOP_HOME` moves the app's data
folder; it also serves tests. Options: `--source TEXT` (`'\chemfig{CH_4}'` makes the error table, `docs/errors.png`),
`--appearance light|dark` (`docs/screenshot-light.png`), `--below` (preview below the editor). Redo the README's pictures
after a UI change.

Release: `./build.sh`, `ditto -c -k --keepParent build/eqpop.app build/eqpop-X.Y.Z-macos-arm64.zip`, then
`gh release create vX.Y.Z build/eqpop-X.Y.Z-macos-arm64.zip --prerelease` (tag `vX.Y.Z` is pushed with the commit).
The zip is Apple Silicon only, ad-hoc signed, not notarized.

## Icon and fonts

`design/logo.swift` draws the icon candidates (`swift design/logo.swift design/out`; `design/out/` is ignored) and
`design/make-icns.sh` turns `design/out/d.png` into `design/eqpop.icns`, which `build.sh` copies into the app. The
text is set in STIX (SIL OFL, shipped with macOS), centred by its ink; the menu-bar `f(x)` is drawn in code from the
same font as a template image. Do not use Apple's SF Symbols or a proprietary font in the icon or logo.

## Layout notes

The window's rows run in one vertical constraint chain (`applyLayout`): the preview goes above the editor or below it.
Editors have a line-number gutter (`LineNumbers.swift`). View-menu toggles are validated in `validateMenuItem`.
