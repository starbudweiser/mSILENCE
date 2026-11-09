import AppKit
import Foundation

/// Une appli bloquée : chemin de son paquet .app (ses helpers et processus enfants sont bloqués avec elle).
struct BlockedApp: Codable, Identifiable, Hashable {
    var path: String
    var addedAt = Date()
    /// Interrupteur propre à l'appli : désactivée, elle reste dans la liste mais n'est plus bloquée.
    var enabled = true
    var id: String { path }
    var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    init(path: String) { self.path = path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Paquet .app qui contient `path` (un helper dans Foo.app/Contents/… compte pour Foo.app) ; sinon `path` lui-même.
func enclosingBundle(_ path: String) -> String {
    let parts = path.split(separator: "/", omittingEmptySubsequences: true)
    guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return path }
    return "/" + parts[...i].joined(separator: "/")
}

/// Chemin sans lien symbolique (/tmp → /private/tmp) : celui que le système donne pour un processus.
func resolvedPath(_ path: String) -> String {
    var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
    return realpath(path, &buf) != nil ? String(cString: buf) : path   // realpath garde /private, contrairement à resolvingSymlinksInPath
}

/// Liste des applis bloquées, enregistrée dans ~/Library/Application Support/mSILENCE/rules.json
/// (MSILENCE_DATA_DIR pour les essais).
@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var apps: [BlockedApp] = []
    /// Appelée après chaque changement, pour envoyer la liste au filtre.
    var onChange: ([String]) -> Void = { _ in }
    /// Interrupteur général : désactivé, plus aucune appli n'est bloquée (la liste est conservée).
    @Published private(set) var globalEnabled: Bool = UserDefaults.standard.object(forKey: "firewallEnabled") as? Bool ?? true
    private let file: URL
    private let marker: URL

    nonisolated static var defaultDirectory: URL {
        if let env = ProcessInfo.processInfo.environment["MSILENCE_DATA_DIR"] { return URL(fileURLWithPath: env) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mSILENCE")
    }

    init(directory: URL = RuleStore.defaultDirectory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("rules.json")
        marker = directory.appendingPathComponent(".radio-silence-imported")
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([BlockedApp].self, from: data) { apps = list }
    }

    var paths: [String] { apps.map(\.path) }
    /// Chemins réellement bloqués : applis cochées, et seulement si l'interrupteur général est actif.
    /// Chemin saisi et chemin résolu (liens symboliques), pour que le filtre reconnaisse l'appli dans les deux cas.
    var activePaths: [String] {
        guard globalEnabled else { return [] }
        return Array(Set(apps.filter(\.enabled).flatMap { [$0.path, resolvedPath($0.path)] })).sorted()
    }
    func isBlocked(_ path: String) -> Bool {
        let b = enclosingBundle(path)
        return apps.contains { ($0.path == b || resolvedPath($0.path) == b) && $0.enabled }
    }

    func setEnabled(_ path: String, _ on: Bool) {
        guard let i = apps.firstIndex(where: { $0.path == path }), apps[i].enabled != on else { return }
        apps[i].enabled = on
        save()
    }

    func setGlobal(_ on: Bool) {
        guard on != globalEnabled else { return }
        globalEnabled = on
        UserDefaults.standard.set(on, forKey: "firewallEnabled")
        onChange(activePaths)
    }

    /// Ajoute des applis ; renvoie le nombre d'ajouts réels.
    @discardableResult
    func add(_ newPaths: [String]) -> Int {
        var added = 0, changed = false
        for p in newPaths.map(enclosingBundle) where !p.isEmpty && p.hasPrefix("/") {
            if let i = apps.firstIndex(where: { $0.path == p || resolvedPath($0.path) == p }) {
                if !apps[i].enabled { apps[i].enabled = true; changed = true }   // « Bloquer » réactive une appli désactivée
            } else {
                apps.append(BlockedApp(path: p)); added += 1
            }
        }
        if added > 0 || changed { save() }
        return added
    }

    func remove(_ path: String) {
        apps.removeAll { $0.path == path }
        save()
    }

    private func save() {
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(apps) { try? data.write(to: file, options: .atomic) }
        onChange(activePaths)
    }

    /// Première ouverture : reprend la configuration de Radio Silence si elle existe.
    func importOnFirstLaunch() {
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        FileManager.default.createFile(atPath: marker.path, contents: nil)
        if let list = RadioSilenceImport.blacklist() { add(list) }
    }
}

/// Lecture de la configuration de Radio Silence (com.radiosilenceapp.client) : liste noire d'applis uniquement.
/// La licence et les autres réglages ne sont jamais repris.
enum RadioSilenceImport {
    static let domain = "com.radiosilenceapp.client"

    static func blacklist() -> [String]? {
        if let v = CFPreferencesCopyAppValue("blacklist" as CFString, domain as CFString) as? [String] { return v }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(domain).plist")
        guard let d = NSDictionary(contentsOf: url), let v = d["blacklist"] as? [String] else { return nil }
        return v
    }
}
