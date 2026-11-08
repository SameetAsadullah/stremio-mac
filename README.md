# Stremio for Mac

[![CI](https://github.com/SameetAsadullah/stremio-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/SameetAsadullah/stremio-mac/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

A personal Mac app that runs [stremio-web](https://github.com/Stremio/stremio-web) with an
[mpv](https://mpv.io) player.

> [!IMPORTANT]
> This is an unofficial, personal project. It is not affiliated with or endorsed by Stremio.
> The app uses Stremio's own web app and Stremio's own streaming server (`server.js`), which it
> downloads from Stremio at first launch. This repository contains only the Mac app that runs
> them.

## Why

The official Stremio app for Mac (5.1.30) uses a lot of battery in fullscreen on a 120 Hz
display. Its player redraws on every display refresh, also when the video has no new frame. This
app redraws only when mpv has a new frame, so a 24 fps video draws 24 times per second. It decodes
in hardware with VideoToolbox.

Measured on a MacBook Pro (M4 Pro) on battery, with a fullscreen 1080p24 video at 120 Hz:

| Setup | Battery draw |
| --- | ---: |
| Idle desktop | 4.24 W |
| This app, real web player | 5.81 W |
| Official Stremio 5.1.30 | 14 to 16 W |

The cause and the fix are reported to Stremio in
[stremio-bugs#2927](https://github.com/Stremio/stremio-bugs/issues/2927).

## Status

Version 0.1.0 opens stremio-web in a window and answers its shell protocol. Login persists across
restarts, and links that open a new window go to the default browser. An mpv player shows video
under the web view and draws only when a new frame arrives. The app also runs Stremio's
streaming server as a child `node` process, or uses the one that already answers on port 11470.
Torrent streams play through the server and mpv.

Mac features:

- The display stays awake while a video plays and is not paused. Playback state comes from mpv's
  `pause` and `idle-active` properties, so nothing polls or runs on a timer.
- Now Playing and the media keys work: the title, artist, artwork, duration and position show in
  Control Center. Play, pause, play/pause, next and seek work from the keyboard and Control
  Center. The keys belong to the app only while a file is loaded.
- Full screen is native macOS full screen. The web's full screen button, F and Esc stay in sync
  with it, and minimizing the window pauses the video when stremio-web's "pause on minimize"
  setting is on.
- Closing the window quits the app, so the streaming server always ends with it.
- `stremio://` and `magnet:` links and `.torrent` files open in the app, as in the official app.
  A link that arrives during launch waits until stremio-web is ready.

## Requirements

- macOS 14 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Apple Silicon. The bundled Node.js binary is arm64 only.

## Install

Build the app from source and copy it to `~/Applications`:

```bash
brew install xcodegen
make bootstrap
make install
```

`make install` builds a Release app, copies it to `~/Applications/Stremio.app` and checks the
signature with `codesign --verify --deep --strict`. It never touches `/Applications/Stremio.app`
and refuses to replace an app in `~/Applications` that has another bundle identifier.

`make dist` builds a Release app and writes `build/Stremio-mac-<version>.zip`. The zip is ad-hoc
signed and not notarized. On another Mac, remove the quarantine flag after you unzip it:

```bash
xattr -dr com.apple.quarantine ~/Applications/Stremio.app
```

Or right-click the app and choose Open. The app runs on Apple Silicon only, with macOS 14 or
later.

The app runs next to the official app. It has its own data folder, uses a server of the official
app that already runs and leaves links to the official app until you change the default. At first
launch it downloads `server.js` once. The Stremio login is separate from the official app, so sign
in again. Both apps have the name Stremio. In Spotlight, this app is the one in `~/Applications`.

To open `stremio://` and `magnet:` links and `.torrent` files in this app instead of the official
app, run:

```bash
make default
```

To go back, run `scripts/make-default.sh /Applications/Stremio.app`.

## Build

```bash
brew install xcodegen
make bootstrap
make build
```

`make bootstrap` downloads Node.js 24.22.2 from nodejs.org into `Vendor/node/` and checks its
SHA-256. `make build` and `make test` run it when needed.

`make open` generates the project and opens it in Xcode. `make run` builds and starts the app.
`make test` runs the unit tests. `make lint` checks the code with `swift-format`.

To play a local file or URL without the web player, start the app with `-play`:

```bash
build/DerivedData/Build/Products/Debug/Stremio.app/Contents/MacOS/Stremio -play ~/Movies/test.mp4
```

Every 10 seconds the app then logs the number of draws, the hardware decoder and the dropped
frames. To see the log, run
`log stream --predicate 'subsystem == "com.sameetasadullah.stremio-mac"'`.

The app uses the LGPL build of [MPVKit](https://github.com/mpvkit/MPVKit), version 1.0.0.

## Streaming server

At first launch the app downloads Stremio's `server.js` 4.21.1 from `dl.strem.io` to
`~/Library/Application Support/com.sameetasadullah.stremio-mac/` and keeps it only when its
SHA-256 matches. `server.js` is proprietary, so it is never in this repository or in the app.
The download does not block the window.

- If a Stremio server already answers on `http://127.0.0.1:11470/settings`, such as the official
  app's, the app uses it and starts none.
- Otherwise the app starts the bundled `node` with a preload script. The preload binds the HTTP
  ports to `127.0.0.1` and ends node when the app's stdin pipe closes, so node does not outlive
  the app, even after a crash or `kill -9`. If node dies, the app restarts it twice, after 1 s
  and 5 s.
- Data is in `~/Library/Application Support/com.sameetasadullah.stremio-mac/server`. The app
  never writes to the official app's `stremio-server` folder. The log is
  `~/Library/Logs/com.sameetasadullah.stremio-mac/server.log`.
- `-server-port 11471` moves the server to another port, to test next to the official app.

### Web mirror

`web.stremio.com` is an HTTPS page, and WebKit blocks it from calling `http://127.0.0.1:11470`
(mixed content). So the app serves the web app itself from `http://127.0.0.1:11480/`, a loopback
server that mirrors `web.stremio.com`. A localhost page may call the streaming server. The port
is fixed so that the login survives restarts, and the mirror listens on `127.0.0.1` only. Links to
`web.stremio.com` open in the app and other links open in the default browser.

## Related

[stremio-ios](https://github.com/SameetAsadullah/stremio-ios) runs Stremio with torrent
streaming on an iPhone or iPad.

## License

[MIT](LICENSE)
