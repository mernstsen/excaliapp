// Bundles Excalidraw into ExcaliApp/Web.bundle, which Xcode copies into the
// app as a single resource folder. Run `npm run build` after changing web/src
// or bumping @excalidraw/excalidraw.
import * as esbuild from "esbuild";
import { cp, mkdir, rm, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(root, "..", "ExcaliApp", "Web.bundle");
const dist = path.join(
  root,
  "node_modules",
  "@excalidraw",
  "excalidraw",
  "dist",
  "prod",
);

// Xiaolai is a 12 MB CJK face; the other eight cover Excalidraw's own UI and
// every default font family. Set EXCALIAPP_ALL_FONTS=1 to ship it too.
const skipFonts = process.env.EXCALIAPP_ALL_FONTS ? [] : ["Xiaolai"];

await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });

await esbuild.build({
  entryPoints: [path.join(root, "src", "main.jsx")],
  outfile: path.join(out, "app.js"),
  bundle: true,
  minify: true,
  format: "iife",
  target: ["safari18"],
  jsx: "automatic",
  legalComments: "none",
  // The package's "." and "./index.css" subpaths are condition-gated.
  conditions: ["production"],
  define: { "process.env.NODE_ENV": '"production"' },
  // index.css points at ./fonts/...; leave those URLs alone and ship the
  // directory as-is next to app.css.
  external: ["./fonts/*"],
  loader: { ".woff2": "file" },
});

await cp(path.join(root, "src", "index.html"), path.join(out, "index.html"));

for (const family of await readdir(path.join(dist, "fonts"))) {
  if (skipFonts.includes(family)) {
    continue;
  }
  await cp(
    path.join(dist, "fonts", family),
    path.join(out, "fonts", family),
    { recursive: true },
  );
}

console.log(`built -> ${path.relative(path.join(root, ".."), out)}`);
