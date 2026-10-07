# Neovarch Agent — landing page

Promo site for Neovarch Agent, built with Next.js (App Router, TypeScript, React) and exported as static HTML.

Lives in `landing/` inside the Flutter repo and is fully independent of the app.

## Commands

```bash
npm install          # install dependencies (Node 20+)
npm run dev          # dev server at http://localhost:3000
npm run build        # static export -> out/ (out/index.html)
npm run typecheck    # tsc --noEmit
npm start            # serve the exported out/ folder locally
```

`next.config.ts` sets `output: 'export'` and `images.unoptimized`, so `npm run build` writes a plain static site to `out/`.

## GitHub Pages

For a project page served from a sub-path (e.g. `https://<user>.github.io/neovrach_Agent/`), build with the path set:

```bash
BASE_PATH=/neovrach_Agent npm run build
```

Then publish the contents of `out/` (add an empty `out/.nojekyll` so `_next/` is served).

## Layout

- `app/` — root layout (fonts via `next/font`), page, global tokens in `globals.css`
- `components/` — Hero, WhatItIs, Features, HowItWorks, SharedOffice, Comparison, Footer, plus shared SectionHead, ArtFigure, CardGrid, CtaLinks
- `lib/site.ts` — repo URL, section list, `asset()` base-path helper
- `public/art/` — artwork
