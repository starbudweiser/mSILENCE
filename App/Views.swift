import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Tab: Hashable, CaseIterable {
    case blocked, monitor, settings
    var title: String {
        switch self {
        case .blocked: L("tab.blocked")
        case .monitor: L("tab.monitor")
        case .settings: L("tab.settings")
        }
    }
}

private enum Icons {
    @MainActor static var cache: [String: NSImage] = [:]
    @MainActor static func icon(_ path: String) -> NSImage {
        if let i = cache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        cache[path] = i
        return i
    }
}

struct RootView: View {
    @ObservedObject var rules: RuleStore
    @ObservedObject var fw: FirewallController
    @State var tab: Tab = .blocked
    init(rules: RuleStore, fw: FirewallController, tab: Tab = .blocked) { self.rules = rules; self.fw = fw; _tab = State(initialValue: tab) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space4) {
                Text("mSILENCE").socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                SocleSegmented(options: Tab.allCases, selection: tab, label: \.title) { tab = $0 }
                Spacer()
                StatusBadge(state: fw.state, paused: !rules.globalEnabled)
                Toggle(isOn: Binding(get: { rules.globalEnabled }, set: { rules.setGlobal($0) })) {
                    Text(L("firewall.toggle")).socle(Socle.T.label).foregroundStyle(Socle.C.text)
                }
                .toggleStyle(.switch).controlSize(.small).tint(Socle.C.accentFill)
            }
            .padding(.horizontal, Socle.M.space6)
            .frame(height: Socle.M.sizeBar + 12)
            .background(Socle.C.surfaceRaised)
            Rectangle().fill(Socle.C.border).frame(height: 1)
            Group {
                switch tab {
                case .blocked: BlockedView(rules: rules, fw: fw)
                case .monitor: MonitorView(rules: rules, fw: fw)
                case .settings: SettingsView(rules: rules, fw: fw)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Socle.C.bg)
        .frame(minWidth: 720, minHeight: 520)
        .onChange(of: tab) { _, t in t == .monitor ? fw.startMonitoring() : fw.stopMonitoring() }
    }
}

struct StatusBadge: View {
    let state: FirewallController.State
    var paused = false
    var body: some View {
        let (text, color): (String, Color) = switch state {
        case .active where paused: (L("status.paused"), Socle.C.warning)
        case .active: (L("status.active"), Socle.C.success)
        case .installing: (L("status.installing"), Socle.C.warning)
        case .needsApproval: (L("status.approval"), Socle.C.warning)
        case .failed: (L("status.failed"), Socle.C.danger)
        default: (L("status.off"), Socle.C.textMuted)
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).socle(Socle.T.label).foregroundStyle(color)
        }
    }
}

// MARK: Blocage

struct BlockedView: View {
    @ObservedObject var rules: RuleStore
    @ObservedObject var fw: FirewallController
    @State private var dropping = false

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("blocked.title")).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                    Text(L("blocked.subtitle")).socle(Socle.T.body).foregroundStyle(Socle.C.accentText)
                }
                Spacer()
                Button(L("blocked.add")) { Self.choose(rules) }.buttonStyle(SocleButtonStyle(.action)).fixedSize()
            }
            if fw.state != .active { FirewallNotice(state: fw.state, fw: fw, rules: rules) }
            ZStack {
                if rules.apps.isEmpty {
                    VStack(spacing: Socle.M.space2) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 30)).foregroundStyle(Socle.C.textSubtle)
                        Text(L("blocked.empty")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).multilineTextAlignment(.center)
                    }.padding(Socle.M.space6)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rules.apps) { app in
                                BlockedRow(app: app, paused: !rules.globalEnabled,
                                           onToggle: { rules.setEnabled(app.path, $0) }, onRemove: { rules.remove(app.path) })
                                if app.id != rules.apps.last?.id { Rectangle().fill(Socle.C.borderSubtle).frame(height: 1) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropping ? Socle.C.surfaceHover : Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(dropping ? Socle.C.accent : Socle.C.border, lineWidth: 1))
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in rules.add([url.path]) } }
                    }
                }
                return true
            }
            Text(L("blocked.count", rules.apps.count)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
        }
        .padding(Socle.M.space6 + 4)
    }

    @MainActor static func choose(_ rules: RuleStore) {
        let panel = NSOpenPanel()
        panel.title = L("blocked.panel")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK { rules.add(panel.urls.map(\.path)) }
    }
}

struct BlockedRow: View {
    let app: BlockedApp
    let paused: Bool
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void
    static let rowHeight: CGFloat = 58
    var body: some View {
        HStack(alignment: .center, spacing: Socle.M.space3) {
            Toggle("", isOn: Binding(get: { app.enabled }, set: onToggle))
                .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Socle.C.accentFill)
            Image(nsImage: Icons.icon(app.path)).resizable().frame(width: 32, height: 32).opacity(app.exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong)
                Text(app.exists ? app.path : "\(L("blocked.missing")) · \(app.path)").socle(Socle.T.meta)
                    .foregroundStyle(app.exists ? Socle.C.accentText : Socle.C.warning).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Socle.M.space3)
            Button(L("blocked.delete"), action: onRemove).buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
        }
        .padding(.horizontal, Socle.M.space4)
        .frame(height: Self.rowHeight)   // même hauteur pour toutes les lignes, contenu centré
        .opacity(app.enabled && !paused ? 1 : 0.55)
    }
}

/// Encart quand le filtre n'est pas encore actif : dit pourquoi et propose l'action.
struct FirewallNotice: View {
    let state: FirewallController.State
    @ObservedObject var fw: FirewallController
    @ObservedObject var rules: RuleStore

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            Text(message).socle(Socle.T.body).foregroundStyle(Socle.C.warningSoft)
            HStack {
                switch state {
                case .needsApproval:
                    Button(L("notice.openSettings")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                case .installing: EmptyView()
                default:
                    Button(L("settings.install")) { fw.install(paths: rules.activePaths) }
                        .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
        }
        .padding(Socle.M.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.warningBg, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.warningBorder, lineWidth: 1))
    }

    private var message: String {
        switch state {
        case .needsApproval: L("notice.approval")
        case .installing: L("notice.installing")
        case .failed(let e): L("notice.failed", e)
        default: L("notice.off")
        }
    }
}

// MARK: Moniteur

struct MonitorView: View {
    @ObservedObject var rules: RuleStore
    @ObservedObject var fw: FirewallController

    private struct Group: Identifiable {
        var path: String
        var count: Int
        var blockedCount: Int
        var last: FlowEvent
        var id: String { path }
    }

    private var groups: [Group] {
        var map: [String: Group] = [:]
        for e in fw.events {
            let key = enclosingBundle(e.appPath)
            var g = map[key] ?? Group(path: key, count: 0, blockedCount: 0, last: e)
            g.count += 1
            if e.blocked { g.blockedCount += 1 }
            if e.date >= g.last.date { g.last = e }
            map[key] = g
        }
        return map.values.sorted { $0.last.date > $1.last.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("monitor.title")).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                Text(L("monitor.subtitle")).socle(Socle.T.body).foregroundStyle(Socle.C.accentText)
            }
            if fw.state != .active { FirewallNotice(state: fw.state, fw: fw, rules: rules) }
            ZStack {
                if groups.isEmpty {
                    Text(L("monitor.empty")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).multilineTextAlignment(.center)
                        .padding(Socle.M.space6)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(groups) { g in
                                row(g)
                                if g.id != groups.last?.id { Rectangle().fill(Socle.C.borderSubtle).frame(height: 1) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
        }
        .padding(Socle.M.space6 + 4)
    }

    @ViewBuilder private func row(_ g: Group) -> some View {
        let blocked = rules.isBlocked(g.path)
        HStack(spacing: Socle.M.space3) {
            Image(nsImage: Icons.icon(g.path)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(((g.path as NSString).lastPathComponent as NSString).deletingPathExtension)
                    .socle(Socle.T.label).foregroundStyle(Socle.C.textStrong)
                Text(L("monitor.last", "\(g.last.host):\(g.last.port)", g.last.proto)).socle(Socle.T.meta)
                    .foregroundStyle(Socle.C.accentText).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Socle.M.space3)
            VStack(alignment: .trailing, spacing: 2) {
                Text(L("monitor.connections", g.count)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                if g.blockedCount > 0 {
                    Text(L("monitor.dropped", g.blockedCount)).socle(Socle.T.meta).foregroundStyle(Socle.C.danger)
                }
            }
            if blocked {
                Button(L("blocked.unblock")) { rules.setEnabled(rules.apps.first { $0.path == g.path || resolvedPath($0.path) == g.path }?.path ?? g.path, false) }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
            } else {
                Button(L("monitor.block")) { rules.add([g.path]) }.buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
            }
        }
        .padding(.horizontal, Socle.M.space4)
        .frame(height: BlockedRow.rowHeight)
    }
}

// MARK: Réglages

struct SettingsView: View {
    @ObservedObject var rules: RuleStore
    @ObservedObject var fw: FirewallController
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var importMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Socle.M.space4) {
                card(L("settings.firewall")) {
                    HStack {
                        StatusBadge(state: fw.state, paused: !rules.globalEnabled)
                        Spacer()
                        if fw.state == .active {
                            Button(L("settings.disable")) { fw.disable() }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        } else if fw.state != .installing {
                            Button(L("settings.install")) { fw.install(paths: rules.activePaths) }
                                .buttonStyle(SocleButtonStyle(.primary, height: Socle.M.sizeControl)).fixedSize()
                        }
                    }
                    Text(L("settings.firewall.hint")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                }
                card(L("settings.import")) {
                    Text(L("settings.import.hint")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                    HStack {
                        Button(L("settings.import.button")) {
                            if let list = RadioSilenceImport.blacklist() {
                                importMessage = L("settings.import.done", rules.add(list), list.count)
                            } else { importMessage = L("settings.import.none") }
                        }.buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                        if let importMessage { Text(importMessage).socle(Socle.T.body).foregroundStyle(Socle.C.success) }
                    }
                }
                card(L("settings.updates")) {
                    Toggle(isOn: $autoUpdate) { Text(L("settings.updates.auto")).socle(Socle.T.body).foregroundStyle(Socle.C.text) }
                        .toggleStyle(.checkbox)
                    Button(L("menu.updates")) { UpdateEngine.shared.checkNow() }
                        .buttonStyle(SocleButtonStyle(.secondary, height: Socle.M.sizeControl)).fixedSize()
                }
            }
            .frame(maxWidth: 720)
            .padding(Socle.M.space6 + 4)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            Text(title).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
            content()
        }
        .padding(Socle.M.space6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusLg).stroke(Socle.C.border, lineWidth: 1))
    }
}
