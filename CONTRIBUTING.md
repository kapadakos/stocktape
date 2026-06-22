# Contributing to StockTape

Thanks for your interest in improving StockTape! This is a small, dependency-free
macOS app and contributions of all sizes are welcome.

## Development Environment

1. Install **Xcode 15 or later** (full Xcode, not just the Command Line Tools —
   `xcodebuild` requires it).
2. Clone the repo and open the project:
   ```bash
   git clone https://github.com/{user}/stocktape.git
   cd stocktape/StockTape
   open StockTape.xcodeproj
   ```
3. Build and run with **Cmd+R**.

### Debugging tip

StockTape ships as a menu-bar-only agent (`LSUIElement = YES`), so it has no
Dock icon and no debugger-friendly main window. While developing, you can
temporarily set `LSUIElement` to `NO` in `StockTape/Info.plist` so the app shows
in the Dock and behaves normally under the Xcode debugger. **Revert this before
committing.**

### Project layout

```
StockTape/StockTape/
├── StockTapeApp.swift     App entry point
├── AppDelegate.swift      Status item, lifecycle, scheduler, wiring
├── Auth/                  OAuth flow + loopback callback server
├── API/                   Schwab client + Decodable models
├── UI/                    Marquee, dropdown menu, onboarding window
├── Utilities/             Market hours, Keychain, file logger
└── Config/                Constants.swift — all tunables in one place
```

## No Credentials, Ever

- **Never commit credentials, tokens, or secrets.** There are no shared API
  keys in this project and there never should be.
- The `.gitignore` excludes `*.xcconfig`, `.env`, and similar files. Do not
  remove those rules, and do not add files that contain secrets.
- If you need credentials to test, register your own free Schwab Developer app
  (see the README) and enter them through the onboarding window — they go
  straight to your Keychain.

## Pull Request Process

- **One feature or fix per PR.** Keep changes focused and easy to review.
- Your branch **must build cleanly in CI** (GitHub Actions builds every PR
  against `main` on a macOS runner).
- Update the README or other docs if your change affects user-facing behavior.
- Describe what you changed and why, and how you tested it.

## Code Style

- Follow **[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) defaults.**
  If you have it installed, run `swiftformat .` before committing.
- Match the surrounding code: clear names, small functions, and comments that
  explain *why* rather than *what*.

## Reporting Issues

Use the issue templates:

- **Bug Report** — for things that don't work as expected.
- **Feature Request** — for new ideas.

When attaching logs from `~/.stocktape/stocktape.log`, double-check that you are
not pasting anything sensitive (StockTape never logs tokens, but verify anyway).
