import AppKit
import SwiftUI

/// Rendus hors écran pour vérifier l'interface sans ouvrir de fenêtre devant le travail en cours.
@MainActor
enum Capture {
    static var sampleEvents: [FlowEvent] {
        let now = Date()
        return [
            FlowEvent(date: now, appPath: "/Applications/Safari.app/Contents/MacOS/Safari", host: "17.253.144.10", port: "443", proto: "TCP", blocked: false),
            FlowEvent(date: now.addingTimeInterval(-3), appPath: "/Applications/Kyno.app/Contents/MacOS/Kyno", host: "52.84.12.9", port: "443", proto: "TCP", blocked: true),
            FlowEvent(date: now.addingTimeInterval(-9), appPath: "/System/Applications/Mail.app/Contents/MacOS/Mail", host: "142.250.74.109", port: "993", proto: "TCP", blocked: false),
        ]
    }

    static func main(rules: RuleStore, fw: FirewallController, tab: Tab, path: String) {
        let view = NSHostingView(rootView: RootView(rules: rules, fw: fw, tab: tab))
        view.frame = NSRect(x: 0, y: 0, width: 960, height: 625)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { write(view, path) } }
    }

    static func about(_ path: String) {
        About.show()
        guard let window = NSApp.windows.first(where: { $0.title == L("about.menu") }), let view = window.contentView else { exit(1) }
        window.orderOut(nil)
        window.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor
        write(view, path)
    }

    private static func write(_ view: NSView, _ path: String) {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}
