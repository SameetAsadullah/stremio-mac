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
  window signals back. Player calls go to a `PlayerBackend` protocol that only logs for now.
- External links open in the default browser.
- Unit tests and a `make test` step in CI.
