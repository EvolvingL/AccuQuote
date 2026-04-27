# App Icons

Generate PNG icons from `icon.svg` before deploying.

Required sizes:
- `icon-32.png`   — browser favicon
- `icon-96.png`   — PWA shortcut
- `icon-180.png`  — Apple touch icon
- `icon-192.png`  — PWA manifest
- `icon-512.png`  — PWA manifest (large)

## Quickest way to generate (macOS)

Install `sharp-cli`:
```bash
npm install -g sharp-cli
```

Then run from the `/icons` directory:
```bash
sharp -i icon.svg -o icon-32.png resize 32 32
sharp -i icon.svg -o icon-96.png resize 96 96
sharp -i icon.svg -o icon-180.png resize 180 180
sharp -i icon.svg -o icon-192.png resize 192 192
sharp -i icon.svg -o icon-512.png resize 512 512
```

Or use any online SVG-to-PNG converter (e.g. svgtopng.com).

For App Store submission you also need a 1024×1024 PNG with no transparency.
