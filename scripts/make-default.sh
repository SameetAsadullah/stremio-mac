#!/bin/sh
# Makes the app the default for stremio:// and magnet: links and .torrent files.
# Usage: scripts/make-default.sh [path to Stremio.app]
set -eu

APP="${1:-$HOME/Applications/Stremio.app}"
[ -d "$APP" ] || { echo "No app at $APP. Run make install first." >&2; exit 1; }

# Launch Services must know the app's link types before it can be the default.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

swift - "$APP" <<'EOF'
import AppKit
import UniformTypeIdentifiers

let app = URL(fileURLWithPath: CommandLine.arguments[1])
let workspace = NSWorkspace.shared
var pending = 3
var failed = false

func done(_ what: String) -> (Error?) -> Void {
    { error in
        DispatchQueue.main.async {
            if let error {
                print("\(what) failed: \(error.localizedDescription)")
                failed = true
            } else {
                print("\(what) open in \(app.path)")
            }
            pending -= 1
        }
    }
}

for scheme in ["stremio", "magnet"] {
    workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme, completion: done("\(scheme) links"))
}
let torrent = UTType(importedAs: "org.bittorrent.torrent")
workspace.setDefaultApplication(at: app, toOpen: torrent, completion: done(".torrent files"))

while pending > 0 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
exit(failed ? 1 : 0)
EOF
