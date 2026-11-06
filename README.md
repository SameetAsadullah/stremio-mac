# Stremio for Mac

[![CI](https://github.com/SameetAsadullah/stremio-mac/actions/workflows/ci.yml/badge.svg)](https://github.com/SameetAsadullah/stremio-mac/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![License](https://img.shields.io/badge/license-MIT-blue)

A personal Mac app that runs [stremio-web](https://github.com/Stremio/stremio-web) with an
[mpv](https://mpv.io) player.

The goal is lower battery use in fullscreen at 120 Hz. The official Stremio app draws about 16 W
in that case. A player that draws only when a new video frame arrives measured about 5.5 W.

> [!IMPORTANT]
> This is an unofficial, personal project. It is not affiliated with or endorsed by Stremio.

## Status

Version 0.1.0 is a scaffold. It opens one empty window and links MPVKit. The web view, the
player and the streaming server are not built yet.

## Requirements

- macOS 14 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
brew install xcodegen
make generate
make build
```

`make open` generates the project and opens it in Xcode. `make run` builds and starts the app.
`make lint` checks the code with `swift-format`.

The app uses the LGPL build of [MPVKit](https://github.com/mpvkit/MPVKit), version 1.0.0.

## License

[MIT](LICENSE)
