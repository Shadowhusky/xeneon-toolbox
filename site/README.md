# Website

Static site for xeneon.shadowhusky-london.uk (Cloudflare Pages project `xeneon-toolbox`).

- `index.html`, `site.css`, `site.js`: the page. three.js loads `assets/3d/edge.glb` for the hero.
- `3d/edge.py`: builds the panel model and renders `assets/3d/*.png` with Blender 5 headless.
- `tools/promo.sh`: cuts `assets/video/promo.{mp4,webm}` from `docs/img` captures and `assets/audio/theme.mp3`.
- Deploy: `npx wrangler pages deploy site --project-name xeneon-toolbox --branch main`.
