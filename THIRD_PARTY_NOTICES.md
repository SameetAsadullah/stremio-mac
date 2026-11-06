# Third-party notices

The app uses the software below. This repository does not contain the code of any of them. MPVKit
comes from Swift Package Manager, `scripts/bootstrap.sh` downloads Node.js, and the app downloads
Stremio's streaming server at first launch.

| Component | Version | License | How the app uses it |
| --- | --- | --- | --- |
| [MPVKit](https://github.com/mpvkit/MPVKit) | 1.0.0 | LGPL-3.0 | Linked framework, the LGPL build |
| [mpv](https://mpv.io) | As built in MPVKit | LGPL-2.1-or-later in this build | Plays video, inside MPVKit |
| [FFmpeg](https://ffmpeg.org) | As built in MPVKit | LGPL-2.1-or-later in this build | Decodes video, inside MPVKit |
| [Node.js](https://nodejs.org) | 24.22.2 | MIT, plus the licenses of its dependencies | Bundled `node` binary, runs `server.js` |
| [Stremio web app](https://github.com/Stremio/stremio-web) | Current release | GPL-2.0 | Loaded from `web.stremio.com` at run time, not distributed |
| Stremio streaming server (`server.js`) | 4.21.1 | Proprietary, © Smart Code OOD | Downloaded from `dl.strem.io` at first launch, not distributed |

## MPVKit, mpv and FFmpeg

These are free software under the GNU Lesser General Public License. Their source code is at
<https://github.com/mpvkit/MPVKit>, <https://github.com/mpv-player/mpv> and
<https://github.com/FFmpeg/FFmpeg>. MPVKit is a linked framework and the source code of this app
is also available, so you can rebuild the app with a modified version.

## Stremio

Stremio is a trademark of Smart Code OOD. This project is not affiliated with or endorsed by
Smart Code OOD. `server.js` is not free software. Do not add it to this repository or to a
release.
