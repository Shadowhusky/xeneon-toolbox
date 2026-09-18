# Website

Static site for xeneon.shadowhusky-london.uk (Cloudflare Pages project `xeneon-toolbox`).

- `index.html`, `site.css`, `site.js`: one fixed WebGL scene (three.js + bloom) that the scroll position drives through six chapters: power on, the strip, the exploded touch stack, tiles lifting off the glass, night, install. Captions are plain HTML over it; without WebGL the page falls back to static images. `window.__xt.step(seconds)` advances the scene by hand for screenshots in a hidden tab.
- `3d/edge.py`: builds the panel model and renders `assets/3d/*.png` with Blender 5 headless.
- `assets/audio/theme.mp3`: the optional theme behind the Sound toggle (off by default).
- Deploy: `npx wrangler pages deploy site --project-name xeneon-toolbox --branch main`.
