# Polaris

![Polaris — Keep your goals in sight](assets/hero.png)

**A quiet, native macOS menu bar app for the goals that matter.**

[简体中文](README.md) · [Build guide](docs/BUILDING.md) · [MIT License](LICENSE)

Polaris keeps weekly, monthly, yearly and long-term goals close at hand. Open it with a global shortcut, check off an inline step, and return to your work. Built with SwiftUI and AppKit, it stores data locally and offers optional two-way sync with selected Apple Reminders lists. The current goal-focused interface is primarily Simplified Chinese.

<p>
  <img src="assets/screenshots/goals-light.png" width="320" alt="Light mode with fictional goals and inline subtasks" />
  <img src="assets/screenshots/goals-dark.png" width="320" alt="The same fictional goals in dark mode" />
</p>

The hero is AI-generated brand artwork. Product screenshots come from the native app running **fictional demo data**, never personal user data.

## Features

- A pinned goal in the menu bar and a configurable global shortcut, defaulting to `Option–Space`.
- Inline subtasks, editable descriptions, goal periods, natural dates, reminders and recurring goals.
- Multiple goal lists, colored labels, a customizable priority matrix, completed history and JSON import/export.
- Consistent panel dimensions, three surfaces, six accents and optional subtle motion.
- Native transparency and macOS 26 Liquid Glass controls, with material fallbacks on earlier systems.
- Optional Apple Reminders sync. Subtasks stay local and are included in JSON backups; they are not native Apple sub-reminders.

## Build and run

Requires **macOS 14+** to run and **Xcode 26+** to build, including the macOS 26 SDK and icon asset compiler. Apple Silicon on macOS 26 has been tested; Intel and older-system runtime verification are still welcome.

```bash
git clone https://github.com/stardime-bingo/Polaris.git
cd Polaris
./build.sh
open build/Polaris.app
```

This is a **source release**. No Developer ID-signed, Apple-notarized installer is provided yet. Local builds use ad-hoc signing. See the [build guide](docs/BUILDING.md) before distributing your own binaries.

For an isolated demo with generated, fictional data:

```bash
./script/build_and_run.sh --demo
```

The demo has a separate bundle identity and data directory. It disables Reminders writes, notification scheduling, login-item changes and global hotkey registration. The regular development preview is also isolated from production data.

## Data and development

Local JSON lives in `~/Library/Application Support/Polaris/` for command-line builds; sandboxed Xcode builds use the app container. Export backups from More Settings. There is no Polaris account, application sync server or analytics service. See [privacy details](PRIVACY.md).

```bash
./run-tests.sh
./script/test_step_persistence.sh
```

274 logic checks and 11 step-persistence checks are included. CI builds both the command-line and Xcode products; native UI changes still require hands-on verification. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Credits

Based on [Docket by @santoru](https://github.com/santoru/docket), preserving the upstream MIT license, attribution and Git history. Polaris adds goal periods, local subtasks and a Chinese-first native experience. See [NOTICE](NOTICE) and [CHANGELOG.md](CHANGELOG.md).
