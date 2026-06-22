# StockTape

StockTape is a free, open source macOS menu bar app that connects to your
Charles Schwab brokerage account and displays your live positions as a
scrolling, color-coded ticker. It runs entirely on your Mac, talks only to
Schwab, and stores your credentials in the macOS Keychain — there are no shared
API keys, no servers, and no telemetry.

<!-- screenshot -->
<!-- TODO: add a screenshot of the scrolling ticker and the dropdown menu here -->

## Requirements

- macOS 13 Ventura or later
- A Charles Schwab brokerage account
- A free [Schwab Developer](https://developer.schwab.com) account
- Xcode 15 or later (to build the app — there is no pre-built download yet)

## Setup: Getting Your Schwab API Credentials

StockTape uses a **bring-your-own-credentials** model. You register your own
Schwab Developer app and StockTape uses your personal App Key and Secret. They
are never shared and never leave your Mac.

1. Go to <https://developer.schwab.com> and sign in with your Schwab credentials.
2. Click **Create App**.
3. Fill in:
   - **App Name** — e.g. `StockTape`
   - **Description** — anything
   - **App Type** — **Personal Use**
4. Set the **Callback URL** to `https://127.0.0.1` **exactly** — HTTPS, no port
   suffix, no trailing slash.
5. Submit. Approval is usually instant for personal-use apps.
6. Copy your **App Key** (this is your *Client ID*) and your **Secret**.

## Installation

```bash
git clone https://github.com/{user}/stocktape.git
cd stocktape/StockTape
open -a Xcode StockTape.xcodeproj
```

> **Tip:** If the project opens as a plain folder in Finder instead of Xcode,
> right-click `StockTape.xcodeproj` in Finder → **Open With → Xcode**.

Then:

1. Press **Cmd+R** to build and run. StockTape will appear in your menu bar.
2. Once you've confirmed it works, install it so you don't need Xcode open:
   - In Xcode: **Product → Show Build Folder in Finder**
   - Open the `Debug/` folder and drag **`StockTape.app`** to `/Applications`
   - Launch it from `/Applications` — it runs independently of Xcode from now on

> The app is signed "to run locally." If you move it to another Mac, build it
> there too (or sign it with your own Developer ID), because it is not notarized.

## First Launch

1. StockTape opens a **setup window** automatically on first launch.
2. Paste your **App Key** (Client ID) and **Secret**.
3. Click **Connect to Schwab** — your default browser opens the Schwab login.
4. Approve access in the browser.
5. **Important — finishing the connection:** Schwab redirects your browser to
   `https://127.0.0.1`, and because nothing is actually serving that address,
   the browser will show a **"can't connect" / "this site can't be reached"**
   error. **This is expected.** Copy the **full URL** from the browser's
   address bar (it looks like `https://127.0.0.1/?code=...&state=...`) and paste
   it into the StockTape dialog, then click **Connect**.
6. StockTape exchanges the code for tokens and the ticker starts within a few
   seconds.

> **Why the copy/paste step?** Schwab requires the redirect URL to be exactly
> `https://127.0.0.1` (HTTPS, port 443, no path). A desktop app can't safely
> serve that address, so the reliable way to capture the one-time authorization
> code is to copy the redirected URL. StockTape also runs a local loopback
> listener as an automatic fast-path, but the copy/paste flow always works.

## Launch at Login

Click the StockTape menu bar icon → **⚙ Settings → Launch at Login** to toggle
it. This uses the modern `SMAppService` API (macOS 13+).

## Re-authentication

- Schwab **access tokens** expire after 30 minutes — StockTape refreshes them
  silently in the background; you never notice.
- Schwab **refresh tokens** expire after **7 days**. This is a hard Schwab API
  limit that can't be extended.
- **StockTape warns you before it happens.** Within the last 24 hours of your
  session, a dialog appears after the next data fetch asking if you want to
  re-authenticate now. You can do it immediately (takes ~30 seconds) or dismiss
  it and re-authenticate later.
- If the refresh token does expire, StockTape detects it on the next fetch,
  shows **⚠ Auth expired** in the menu bar, and re-opens the Schwab login
  automatically.
- You can also re-authenticate manually at any time:
  **⚙ Settings → Re-authenticate**.

## What You'll See

- A scrolling ticker in the menu bar, e.g.
  `▲ AAPL +1.24%   ·   ▼ NVDA -0.87%   ·   ▲ TSLA +3.41%` — green for up, red
  for down.
- Click the menu bar item for a formatted dropdown of each position's price and
  daily change, plus **Refresh Now**, **Settings**, and **Quit**.
- Refresh cadence is every 5 minutes while the US market is open and every 60
  minutes otherwise. It also refreshes immediately when your Mac wakes from
  sleep.

## Privacy

- Your credentials **never leave your Mac**.
- Client ID, Client Secret, and OAuth tokens are stored only in the **macOS
  Keychain**.
- StockTape communicates only with `api.schwabapi.com`.
- **No analytics, no telemetry, no third-party services.**
- A local log is written to `~/.stocktape/stocktape.log` for troubleshooting. It
  never contains tokens or credentials, and it is rotated automatically.

## Known v1 Limitations

- **Market holidays are not detected.** StockTape treats 09:30–16:00 ET,
  Monday–Friday, as "market open" and refreshes on the faster cadence even on
  holidays. This is harmless — it just refreshes more often than necessary.
- **OAuth requires the copy/paste step** described under *First Launch* because
  of Schwab's `https://127.0.0.1` redirect requirement.
- **No app icon yet** — the asset catalog ships with empty icon slots.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

[MIT](LICENSE)
