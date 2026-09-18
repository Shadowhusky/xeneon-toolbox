# Xeneon Toolbox website brief

Product: **Xeneon Toolbox**, a free macOS app that turns the Corsair Xeneon Edge
(a 14.5-inch, 2560×720 touch strip) into a touch dashboard, launcher and control
deck for the Mac. It embeds its own absolute touch driver (no kernel extension),
so taps, scrolls and edge swipes work like a phone. Free, open source
(github.com/Shadowhusky/xeneon-toolbox), macOS 14+, notarized.

Tagline: **Your Mac, on the Edge.**
Sub: Turn the Corsair Xeneon Edge into a touch dashboard, launcher and control
deck. Live system instruments, a Stream-Deck-style launcher, an ambient clock,
tasks, an assistant and a phone remote — all built for a 2560 × 720 strip.

## Design language: "Obsidian Instrument" (shared with the app)

- Surface: carbon black `#0A0B0D` → `#060708`, tiles `#171A20` → `#0E1014`
  with a lit top edge (`rgba(255,255,255,.11)`) and a dark bottom edge
  (`rgba(0,0,0,.6)`). Wells are `rgba(0,0,0,.3)`.
- Text: bone `#ECE9E1`, secondary `#9C9B95`, faint `#5F615F`.
- Signature: amber `#F5B544`, used for one thing per screen (the primary
  action, an index bar, a lit ring). Secondary: ice `#8FD3F4`.
- Instrument hues: orchid `#C79BFF`, rose `#FF8FA3`, mint `#8BE3B0`,
  sand `#E3C97A`, steel `#A9B4C2`, moss `#9BD97A`, ember `#FF7A59`.
- Type: **Instrument Sans** (UI, headlines, sentence case, no tracked caps)
  and **JetBrains Mono** (numerals, labels, code). Google Fonts.
- Motifs: tick rings (48 ticks over 270°, lit from −225°), lamp dots,
  bezelled glass keys, radius hierarchy 22 / 12 / 8.
- Motion: one orchestrated reveal on load; everything else answers the user.
- Never: purple gradients, emoji, identical card grids with drop shadows,
  uppercase eyebrow labels, "→" in buttons, stock 3D blobs.

## Assets

- Real screenshots (2560×720) in `docs/img/*.png`: dashboard, deck, clock,
  tasks, assistant, web, minimal (ambient), control-center, settings,
  customize, resolution. They ARE the strip's aspect ratio, so they read as
  the panel itself.
- 3D: `site/assets/3d/edge.glb` (the panel), rendered stills in
  `site/assets/3d/*.png`, built by `site/3d/edge.py` (Blender 5.1 headless).
- Music: `site/assets/audio/theme.mp3` (instrumental, 30–40 s, loopable).

## Site

Static, one page, `site/index.html` + `site/site.css` + `site/site.js`,
three.js from cdn.jsdelivr.net for the hero. Hosted on Cloudflare Pages at
`xeneon.shadowhusky-london.uk`. Download button →
`https://github.com/Shadowhusky/xeneon-toolbox/releases/latest/download/XeneonToolbox.zip`.
