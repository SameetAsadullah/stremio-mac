import AppKit

/// The minimum menus macOS expects: quit, text editing shortcuts for the login form, and fullscreen.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("Stremio", [item("Quit Stremio", #selector(NSApplication.terminate(_:)), "q")]))
        main.addItem(
            submenu(
                "Edit",
                [
                    item("Undo", Selector(("undo:")), "z"),
                    item("Redo", Selector(("redo:")), "Z"),
                    .separator(),
                    item("Cut", #selector(NSText.cut(_:)), "x"),
                    item("Copy", #selector(NSText.copy(_:)), "c"),
                    item("Paste", #selector(NSText.paste(_:)), "v"),
                    item("Select All", #selector(NSText.selectAll(_:)), "a"),
                ]))
        let fullscreen = item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        main.addItem(
            submenu(
                "Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"), fullscreen]))
        return main
    }

    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }
}
