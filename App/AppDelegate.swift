import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let rules = RuleStore()
    let firewall = FirewallController()
    private var window: NSWindow?
    private var centered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        installMainMenu()
        let args = CommandLine.arguments
        rules.importOnFirstLaunch()

        // Essais : rendu hors écran, aucune fenêtre (`--capture sortie.png [--tab monitor|settings] [--demo]`, `--capture-about sortie.png`).
        if let i = args.firstIndex(of: "--capture-about"), args.indices.contains(i + 1) { Capture.about(args[i + 1]); return }
        if let i = args.firstIndex(of: "--capture"), args.indices.contains(i + 1) {
            if args.contains("--demo") { firewall.demo(state: .active, events: Capture.sampleEvents) }
            let tab: Tab = args.firstIndex(of: "--tab").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                .map { $0 == "monitor" ? .monitor : $0 == "settings" ? .settings : .blocked } ?? .blocked
            Capture.main(rules: rules, fw: firewall, tab: tab, path: args[i + 1])
            return
        }

        rules.onChange = { [weak self] paths in self?.firewall.push(paths: paths) }
        firewall.refresh(paths: rules.activePaths)
        showWindow(quietly: args.contains("--discret"))

        let updates = UpdateEngine.shared
        updates.configure(repo: "mSILENCE", lang: { Bundle.main.preferredLocalizations.first ?? "en" })
        updates.autoCheck = { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        updates.start()
        updates.installAppMenuItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(quietly: false)
        return false
    }

    private func showWindow(quietly: Bool) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 625),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "mSILENCE"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: RootView(rules: rules, fw: firewall))
            w.setFrameAutosaveName("mSILENCE.main")   // la taille est mémorisée ; la position ne l'est jamais (règle Socle « Lancement centré »)
            w.setFrameUsingName("mSILENCE.main")
            if let zone = (NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
                var size = w.frame.size
                size.width = min(size.width, zone.width); size.height = min(size.height, zone.height)
                w.setContentSize(w.contentRect(forFrameRect: NSRect(origin: .zero, size: size)).size)
            }
            w.socleCenter()
            window = w
        }
        if quietly { window?.orderBack(nil) } else { window?.present() }
        if !centered {   // la taille définitive (barre de titre comprise) n'est connue qu'une fois la fenêtre affichée : on recentre alors
            centered = true
            DispatchQueue.main.async { [weak self] in self?.window?.socleCenter() }
        }
    }

    // MARK: Menus (le nom de l'appli reste en texte normal dans les menus)

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("about.menu"), action: #selector(showAbout), keyEquivalent: "").target = self   // Socle : juste au-dessus de « Quitter »
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("menu.edit"))
        edit.addItem(withTitle: L("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let win = NSMenu(title: L("menu.window"))
        win.addItem(withTitle: L("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: L("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = win
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    @objc private func showAbout() { About.show() }
}
