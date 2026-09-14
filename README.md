# nana — Codex usage in your macOS menu bar

`nana` is a tiny, local-only macOS menu bar monitor for Codex usage.

```text
5h 100%  4h25m
1w  84%  3d1h
```

It shows:

- remaining 5-hour Codex usage
- remaining weekly Codex usage
- time until each window resets
- current Codex model / reasoning effort in the dropdown menu

## Privacy

nana does **not** contain or ask for your OpenAI account credentials.

It starts the Codex app-server already installed on your Mac and reads the
local `account/rateLimits/read` response. Authentication remains handled by
your existing Codex installation.

nana has:

- no analytics
- no telemetry
- no external server
- no ads
- no account database
- no token collection

The optional model display reads only local Codex session/config metadata
needed to determine the current model name and reasoning effort.

See [PRIVACY.md](PRIVACY.md) for details.

## Requirements

- macOS
- Codex installed and already signed in
- Xcode Command Line Tools / `swiftc`

## Build and run

```bash
./build.sh --run
```

## Install

```bash
./build.sh --install
```

The app is installed to:

```text
~/Applications/nana-menu.app
```

It runs as a menu-bar-only app and does not show a Dock icon.

## Usage

The menu bar display is intentionally compact:

```text
5h 87%  3h42m
1w 62%  2d7h
```

Click it to view:

- current Codex model
- more detailed quota/reset information
- Refresh now
- Quit nana

Quota data refreshes every 60 seconds.

## Uninstall

Quit nana, then remove:

```bash
rm -rf ~/Applications/nana-menu.app
```

## Security note

nana does not directly read, store, or transmit your OpenAI authentication
token. It asks the local Codex app-server for rate-limit information.

You should still review source code before running software downloaded from
the internet.

## Support

nana is free and open source.

If you find it useful, an optional support link may be added here later.
Using nana will never require a donation.

## License

MIT License. See [LICENSE](LICENSE).

## Disclaimer

This is an independent community project and is not affiliated with or
endorsed by OpenAI. Codex and OpenAI are trademarks of their respective
owners.
