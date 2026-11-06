# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A macOS app scaffold: one resizable window, MPVKit 1.0.0, a Makefile, `swift-format` linting and
  a CI workflow.
- A window that shows stremio-web, with a transparent web view over a black background and a
  saved login.
- A shell bridge that answers stremio-web's `INIT` message, handles its window methods and sends
  window signals back. Player calls go to a `PlayerBackend` protocol.
- External links open in the default browser.
- An mpv player under the web view. It draws only when mpv has a new frame, decodes with
  VideoToolbox and sends mpv's property changes, end of file and first frame to stremio-web.
- A `-play` launch argument that plays a file or URL directly and logs draws every 10 seconds.
- Unit tests and a `make test` step in CI.
- A bundled Node.js 24.22.2 (Apple Silicon only), downloaded and checked by
  `scripts/bootstrap.sh` and signed in the app.
- A streaming server that runs Stremio's `server.js` as a child node process on `127.0.0.1`, uses
  a server that already runs on port 11470, keeps its data and log outside the official app's
  folders, restarts after a crash and ends with the app.
- `THIRD_PARTY_NOTICES.md`.
