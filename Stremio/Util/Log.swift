import os

enum Log {
    static let subsystem = "com.sameetasadullah.stremio-mac"
    static let shell = Logger(subsystem: subsystem, category: "shell")
    static let web = Logger(subsystem: subsystem, category: "web")
    static let player = Logger(subsystem: subsystem, category: "player")
    static let server = Logger(subsystem: subsystem, category: "server")
}
