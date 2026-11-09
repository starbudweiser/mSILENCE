import AppKit
import Foundation

/// Une appli bloquée : chemin de son paquet .app (ses helpers et processus enfants sont bloqués avec elle).
struct BlockedApp: Codable, Identifiable, Hashable {
    var path: String
    var addedAt = Date()
    var id: String { path }
    var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// Paquet .app qui contient `path` (un helper dans Foo.app/Contents/… compte pour Foo.app) ; sinon `path` lui-même.
func enclosingBundle(_ path: String) -> String {
    let parts = path.split(separator: "/", omittingEmptySubsequences: true)
    guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return path }
    return "/" + parts[...i].joined(separator: "/")
}

/// Liste des applis bloquées, enregistrée dans ~/Library/Application Support/mSILENCE/rules.json
/// (MSILENCE_DATA_DIR pour les essais).
@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var apps: [BlockedApp] = []
    /// Appelée après chaque changement, pour envoyer la liste au filtre.
    var onChange: ([String]) -> Void = { _ in }
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
    func isBlocked(_ path: String) -> Bool { paths.contains(enclosingBundle(path)) }

    /// Ajoute des applis ; renvoie le nombre d'ajouts réels.
    @discardableResult
    func add(_ newPaths: [String]) -> Int {
        var added = 0
        for p in newPaths.map(enclosingBundle) where !p.isEmpty && !paths.contains(p) && p.hasPrefix("/") {
            apps.append(BlockedApp(path: p)); added += 1
        }
        if added > 0 { save() }
        return added
    }

    func remove(_ path: String) {
        apps.removeAll { $0.path == path }
        save()
    }

    private func save() {
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(apps) { try? data.write(to: file, options: .atomic) }
        onChange(paths)
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
