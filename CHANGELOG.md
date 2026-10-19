# Changelog

Newest first. One minor version (`0.N.0`) per feature line; every commit after it in that line is a patch.
The version is `eqpopVersion` in `Sources/eqpop/Store.swift`; a change, its entry here and the bump go in one commit.

## 0.2.0 — 2026-10-20

- **Line numbers** in the source and the preamble editors (a wrapped line is numbered once). Menu: View → Line numbers.
- **Preview position.** The preview and its status line go above the editor (the default, as in LaTeXiT) or below it:
  View → Preview above the editor, also in the menu-bar menu. Remembered.
- The preview sheet has a hairline border, so it shows on a light window.
- `--screenshot` takes `--appearance light|dark` and `--below`; the README shows both appearances.
- The appearance was always the system's (the window, text and highlight colours are system colours); this is the
  first release that says so.

## 0.1.5 — 2026-10-20

- `eqpop --screenshot OUT.png [--source TEXT]` writes a picture of the window (title bar, rounded corners, shadow)
  without showing it, on scratch settings and with the default preamble (`EQPOP_HOME` points the app's data folder
  elsewhere); it made `docs/screenshot.png` and `docs/errors.png` for the README.
- README: screenshots, a download for Apple Silicon (a pre-release zip), install notes.

## 0.1.4 — 2026-10-20

- The menu-bar `f(x)` is placed by its outlines: the hook of the italic f was cut off at the left.

## 0.1.3 — 2026-10-20

- **App icon**: an `f(x)` on a teal-to-blue tile, centred by its ink. `design/logo.swift` draws it,
  `design/make-icns.sh` makes `design/eqpop.icns`, which `build.sh` puts in the app. Set in STIX (SIL OFL, shipped
  with macOS), not in a proprietary font.
- The menu-bar icon is the same `f(x)`, drawn in code as a template image (it was Apple's SF Symbol `function`,
  whose licence does not allow it in an icon or logo).

## 0.1.2 — 2026-10-20

- **`./build.sh --install`** builds, quits the running eqpop, copies the app to `~/Applications` and starts it, so
  it opens from Spotlight or Launchpad without the terminal.
- **Launch at login** in the menu-bar menu (macOS login item for the installed copy).

## 0.1.1 — 2026-10-20

- **Live switch.** A checkbox in the window (and the menu) turns rendering-while-typing off. Off: ⌘R renders, ⌘↩
  renders and copies. Remembered.
- **Markdown through pdfmd** (engine `pdfmd`). The source is a Markdown document. eqpop's LaTeX preamble goes
  beside it as `preamble.tex` and a metadata file (the pane's second tab) as `metadata.yaml`, which pdfmd finds as
  it does in a project, so a house style such as nulabreport applies. A second popup picks pdfmd's PDF engine
  (`-e`: auto, tex, lualatex, pdflatex, xelatex, typst, html). Never live: lualatex takes ~10 s, pdflatex ~4 s,
  typst ~1 s. The pdfmd that runs is `$EQPOP_PDFMD`, else `~/dev/py/pdfmd/pdfmd.py` if it exists, else `pdfmd` on the
  search path. The bottom margin of a pdfmd page is left out of the crop (the page number).
- **Error list.** A failed render replaces the preview with a table of every error (line in the source, message,
  the text TeX had just read), as LaTeXiT does; double-click a row to jump to the line. An error above the source is
  marked "(preamble)". `-halt-on-error` is gone so all errors are listed. A **Log** button shows the full log.
- Only the first page of a result is kept; the status line says "page 1 of N".
- `eqpop --render` gained `--pdfmd-engine` and `--metadata`; `--selftest` covers the error-line mapping.

## 0.1.0 — 2026-10-19 (commits 74d0fd3, b46a95c)

First version. Menu-bar popup on a global hotkey (default ⌥⇧T, changeable); live preview; copy as PDF + PNG;
drag the preview out; Save as PDF, PNG or SVG (SVG through `pdftocairo` or `mutool`). pdflatex, lualatex or
xelatex through `standalone`, then a tight crop measured on the ink, so any engine's PDF is cropped the same way.
A compiled-preamble cache for pdflatex (2.4 s → 0.7 s with a house-style package; it follows edits of packages
outside the TeX distribution). A persistent, user-owned preamble file that is never overwritten, edited in an
inline pane. Syntax colours and bracket matching. Headless `eqpop --render` and `eqpop --selftest`.
b46a95c: opening the window keeps the text (it used to select all, so a stray key wiped it).
