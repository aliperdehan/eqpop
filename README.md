# eqpop

A menu-bar popup that renders LaTeX (math, chemistry with `mhchem`, or plain text) to a tightly cropped
vector PDF and puts it on the clipboard. A global hotkey (default ⌥⇧T, changeable from the menu) shows a
floating window; type, watch the live preview, press ⌘↩ to copy (PDF and PNG) and the window hides, giving the
focus back to the app you came from. The preview can also be dragged into Keynote, Word or Finder.

- **Persistent preamble**: `~/Library/Application Support/eqpop/preamble.tex`. Written once on the first launch,
  never overwritten; edit it in the app ("Preamble…") or in any editor. Every render reads it from disk.
- **Auto-crop**: the engine's `standalone` class crops the page, then the ink is measured and the page boxes are
  trimmed to it (any engine's PDF gets the same treatment; the page stays vector).
- **Engines**: `pdflatex`, `lualatex`, `xelatex`, found by absolute path (a Finder-launched app has no PATH).

## Build

    ./build.sh && open build/eqpop.app

Needs only the Command Line Tools and a TeX distribution. The app is ad-hoc signed, not notarized: built on your
own machine it opens normally; a downloaded copy needs System Settings → Privacy & Security → Open Anyway.

## Without the window

    eqpop --render '\ce{2H2 + O2 -> 2H2O}' out.pdf [--inline|--text] [--engine lualatex] [--preamble FILE] [--png FILE]

`open build/eqpop.app --args --show` opens the window at launch (for testing without the hotkey).

## License

MIT.
