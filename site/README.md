# Website

Static site for xeneon.shadowhusky-london.uk (Cloudflare Pages project `xeneon-toolbox`).

- `index.html`, `site.css`, `site.js`: one fixed WebGL scene (three.js + bloom) that the scroll position drives through six chapters: power on, the strip, the exploded touch stack, tiles lifting off the glass, night, install. Captions are plain HTML over it; without WebGL the page falls back to static images. `window.__xt.step(seconds)` advances the scene by hand for screenshots in a hidden tab. A tap on the 3D screen scrolls to the next stop of the tour (its left edge goes back), so the screen and the captions are both driven by the scroll position. Quality adapts both ways: the pixel budget grows while the GPU has room (measured with `EXT_disjoint_timer_query_webgl2` where available, late frames otherwise) up to native resolution and light supersampling, shrinks when frames run long, swaps in `dashboard-2x.webp` once the canvas outresolves the captures, and remembers the level in `localStorage` (`xt.quality`). `window.__xt.quality` reports the current tier.
- `i18n.js`: all page copy in English, 简体中文, 繁體中文 and 日本語. The language follows `?lang=`, then the visitor's last choice, then the browser's language list; CJK fonts load only for the active language.
- `3d/edge.py`: builds the panel model and renders `assets/3d/*.png` with Blender 5 headless.
- `assets/audio/theme.mp3`: the optional theme behind the Sound toggle (off by default).
- Deploy: `npx wrangler pages deploy site --project-name xeneon-toolbox --branch main`.
