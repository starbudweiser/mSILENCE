import AppKit

let arguments = CommandLine.arguments

/// `--import-radio-silence` : reprend la liste noire de Radio Silence sans interface (terminal, essais).
if arguments.contains("--import-radio-silence") {
    MainActor.assumeIsolated {
        let store = RuleStore()
        guard let list = RadioSilenceImport.blacklist() else { print("Aucune configuration Radio Silence trouvée."); exit(1) }
        let n = store.add(list)
        print("\(n) applis ajoutées sur \(list.count) (\(store.apps.count) bloquées au total).")
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
