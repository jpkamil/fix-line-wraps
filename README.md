# Fix Line Wraps

A small Mac app. Drop a hard-wrapped Markdown file on it and every paragraph becomes one line, so the file flows to whatever width the window is. Nothing but whitespace ever changes.

## Why

Documents hard-wrapped at a fixed column read ragged in any narrower window: each source line soft-wraps into one long line and one short remainder. Markdown ignores single newlines, so the rendered page was always fine. The raw file was not, and the raw file is what gets read.

Unwrapping by hand is how a word gets destroyed: two lines joined with no space between them, in the middle of a sentence that still looks plausible. So this tool proves its work instead of asserting it. Before writing, it collapses every run of whitespace in the old text and the new text to one space and refuses to write unless the two are identical. If a single character of actual text would differ, the file is left exactly as it was and the window says so.

It leaves alone everything where the line break is the meaning: fenced code, tables, lists, headings, rules, blockquotes, YAML front matter, HTML blocks, indented lines, a line ending in two spaces, and a leading `To:` / `Subject:` header block.

## Using it

- **Drop** `.md` files, or folders of them, on the window or on the Dock icon.
- **Choose Files…** (⌘O) opens a picker instead.
- The window shows, per file, how many lines were joined, or that it was already fine, or that it was refused.

The command-line tool works on its own too:

```
python3 reflow_md.py FILE...            rewrite, only if provably lossless
python3 reflow_md.py --check FILE...    show what would change, write nothing
python3 reflow_md.py --dir PATH         every .md under PATH
```

## Building and installing

Needs the Xcode Command Line Tools (`xcode-select --install`) for `swiftc`, and any `python3` that runs.

```
./build-app.sh --install    # build and put it in /Applications
./build-app.sh --open       # the same, then launch it
./build-dmg.sh              # a drag-to-Applications image, for a Mac without this repo
```

Then drag it from Applications to the Dock, once.

The built app is ad-hoc signed and not notarized. On a Mac other than the one that built it, macOS asks once: System Settings > Privacy & Security, "Open Anyway".

## How it is put together

| file | what it is |
|---|---|
| `reflow_md.py` | the tool: the reflow and the proof. Python 3, standard library only. |
| `Sources/FixLineWraps.swift` | the app: one window, a drop zone, a report. AppKit, one file. |
| `Packaging/Info.plist` | bundle identity and the document types a drop is accepted for |
| `Packaging/FixLineWrapsIcon.swift` | draws the icon; `render-icon.sh` turns it into the committed `.icns` |
| `build-app.sh`, `build-dmg.sh` | the builds. Output goes to `~/Library/Caches/fix-line-wraps-build/`, never into the repo. |

The app copies each dropped file into a private temporary folder, runs `reflow_md.py` on the copies, and writes back in place only the copies that changed. The app process is the one that holds whatever access the drop or the Open panel granted, so Python never has to read a protected folder (Desktop, Documents, Downloads) itself. The AppleScript droplet this replaced ran the tool through a shell child, which macOS refused those files.

Which `python3` runs: `$COMPASS_PYTHON` if set, then the python.org framework, Homebrew, `/usr/local`, then Apple's `/usr/bin/python3` only when the Command Line Tools are installed, because without them it is a stub that opens an installer dialog and blocks. Each candidate is run, not just found, before it is trusted.
