# Public visual assets

- `hero.png`: promotional artwork made with the built-in image generation tool. The exact prompt is preserved in `hero.prompt.txt`; `brand/icon-light.png` is the brand reference. It is an illustration, not a product screenshot.
- `brand/icon-light.png` and `brand/icon-dark.png`: exported native Polaris app icon variants. The editable app assets live in `Docket/PolarisAB.icon`.
- `screenshots/`: actual native application window captures, with fictional data created by `script/make_demo_data.py` and launched through `./script/build_and_run.sh --demo`. No personal datasets, system permission dialogs or account identifiers are included.
- `screenshots/direct-completion-light-1.5.3.jpg` and `screenshots/direct-completion-dark-1.5.3.jpg`: Polaris 1.5.3's independent goal-completion buttons, including the featured goal and a wrapped title in a compact dark window. These use fictional demo goals; the long cooking title was edited only in the isolated demo.

When updating screenshots, inspect each image for private data and capture the actual UI. Keep generated brand illustrations distinct from screenshots. Do not copy runtime traces, user exports, desktop captures or local audit material into this directory.
