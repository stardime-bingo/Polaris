# Public visual assets

- `hero.png`: promotional artwork made with the built-in image generation tool. The exact prompt is preserved in `hero.prompt.txt`; `brand/icon-light.png` is the brand reference. It is an illustration, not a product screenshot.
- `brand/icon-light.png` and `brand/icon-dark.png`: exported native Polaris app icon variants. The editable app assets live in `Docket/PolarisAB.icon`.
- `screenshots/`: actual native application window captures, with fictional data created by `script/make_demo_data.py` and launched through `./script/build_and_run.sh --demo`. No personal datasets, system permission dialogs or account identifiers are included.

When updating screenshots, inspect each image for private data and capture the actual UI. Keep generated brand illustrations distinct from screenshots. Do not copy runtime traces, user exports, desktop captures or local audit material into this directory.
