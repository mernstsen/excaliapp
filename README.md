<img src="ExcaliApp/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="ExcaliApp icon">

# ExcaliApp

A native macOS app for [Excalidraw](https://excalidraw.com). Your drawings are
plain `.excalidraw` files in a folder you can see in Finder, listed in a
sidebar, saved the way Mac apps save — continuously, with no Save button.

> ExcaliApp is an unofficial personal project. It is not affiliated with,
> endorsed by, or sponsored by Excalidraw.

## What it does

- **A library, not a document shuffle.** One window, with a sidebar listing
  every `.excalidraw` file in your folder, newest first, with search.
- **Real files.** Drawings live in `~/Documents/Excalidraw` as the standard
  Excalidraw JSON format, so they open on excalidraw.com and in any other
  editor. Add, rename or delete files in Finder and the sidebar keeps up.
- **Autosave.** A save lands about 1.5 seconds after you stop drawing, and at
  least every 10 seconds while you keep going. Switching drawings, pressing
  ⌘S, and quitting all flush first — quitting waits for the write to finish.
- **Native chrome.** System sidebar and toolbar, File-menu commands with the
  shortcuts you would expect, Move to Trash rather than deletion, Reveal in
  Finder, and the canvas follows the system light/dark appearance.

| Shortcut | Action |
| --- | --- |
| ⌘N | New drawing |
| ⌘S | Save now |
| ⌘D | Duplicate |
| ⇧⌘R | Reveal in Finder |
| ⌘⌫ | Move to Trash |
| ⌘, | Change the drawings folder |

## Requirements

macOS 27 or later, and Xcode 27 or later to build it.

## Building

Open `ExcaliApp.xcodeproj` and run. Nothing else is needed — the Excalidraw
web bundle is committed, so a clean clone builds with Xcode alone.

Node is needed only to rebuild that bundle, after editing `web/src` or
changing the Excalidraw version:

```sh
npm --prefix web install
npm --prefix web run build
```

That writes `ExcaliApp/Web.bundle` and regenerates `THIRD-PARTY-NOTICES.md`.
To regenerate the app icon:

```sh
./Scripts/make-icon.sh
```

## How it works

Excalidraw is a React app, so it runs in a `WKWebView`. Three things make it
feel like a Mac app rather than a browser window:

- **`web/`** bundles Excalidraw and React into a single self-contained file
  with esbuild. The published Excalidraw package leaves React and its other
  dependencies as bare module specifiers, so a bundling step is unavoidable.
- **`WebBundleSchemeHandler`** serves that bundle over a custom
  `excaliapp://` scheme instead of `file://`, so the page gets a real origin
  and WebKit allows the `fetch` and font loads Excalidraw does at runtime.
- **`EditorBridge`** owns one long-lived web view and decides when the scene
  reaches disk. The canvas reports edits, Swift debounces them, and the
  document is only marked saved once the write succeeds.

Swift sources live in `ExcaliApp/`, which is an Xcode synchronized group — any
`.swift` file there is compiled into the app automatically, which is why
`Scripts/` sits outside it.

## Licence

ExcaliApp is MIT licensed — see [LICENSE](LICENSE).

It embeds Excalidraw (MIT, © 2020 Excalidraw) and its dependencies.
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) lists every bundled package
with its licence, and each font ships its licence next to it in
`ExcaliApp/Web.bundle/fonts/`.

One exception worth knowing about: **Excalifont**, Excalidraw's handwriting
face and the default for new text, carries no licence file. Its embedded
metadata reads "Copyright (c) 2024 by Excalidraw. All rights reserved.", while
the Excalidraw repository it ships in is MIT licensed. Those two disagree, and
the upstream font directories contain no licence file to settle it. It is
bundled here on the basis of that repository licence. If you redistribute this
project and want certainty, ask upstream or drop the `Excalifont` directory —
text then falls back to Nunito.
