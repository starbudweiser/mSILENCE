import Foundation
import NetworkExtension
import SystemExtensions

/// Installe l'extension réseau, lui envoie la liste des applis bloquées et relève les connexions qu'elle voit.
@MainActor
final class FirewallController: NSObject, ObservableObject {
    enum State: Equatable {
        case unknown, notInstalled, installing, needsApproval, active
        case failed(String)
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var events: [FlowEvent] = []
    private var connection: NSXPCConnection?
    private var lastEvent = Date.distantPast
    private var paths: [String] = []
    private var poller: Timer?

    // MARK: État

    func refresh(paths: [String]) {
        self.paths = paths
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let mgr = NEFilterManager.shared()
                if let error { self.state = .failed(error.localizedDescription); return }
                if self.state == .installing || self.state == .needsApproval { return }
                self.state = (mgr.providerConfiguration != nil && mgr.isEnabled) ? .active : .notInstalled
            }
        }
    }

    // MARK: Installation

    func install(paths: [String]) {
        self.paths = paths
        state = .installing
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Shared.extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Désactive le filtre (l'extension reste installée, sans filtrer).
    func disable() {
        let mgr = NEFilterManager.shared()
        mgr.loadFromPreferences { _ in
            mgr.isEnabled = false
            mgr.saveToPreferences { error in
                Task { @MainActor in self.state = error == nil ? .notInstalled : .failed(error!.localizedDescription) }
            }
        }
    }

    /// Envoie la liste au filtre : elle est conservée dans la configuration du système, donc active dès le démarrage du Mac.
    func push(paths: [String]) {
        self.paths = paths
        guard state == .active else { return }
        saveConfiguration()
    }

    private func saveConfiguration() {
        let mgr = NEFilterManager.shared()
        let list = paths
        mgr.loadFromPreferences { error in
            if let error { Task { @MainActor in self.state = .failed(error.localizedDescription) }; return }
            let conf = NEFilterProviderConfiguration()
            conf.filterSockets = true
            conf.filterPackets = false
            conf.vendorConfiguration = [Shared.rulesKey: list]
            mgr.providerConfiguration = conf
            mgr.localizedDescription = "mSILENCE"
            mgr.isEnabled = true
            mgr.saveToPreferences { error in
                Task { @MainActor in
                    if let error {
                        let ns = error as NSError
                        // 4 : en attente de l'autorisation de l'utilisateur dans Réglages Système
                        self.state = ns.domain == NEFilterErrorDomain && ns.code == NEFilterManagerError.configurationPermissionDenied.rawValue
                            ? .needsApproval : .failed(error.localizedDescription)
                    } else {
                        self.state = .active
                    }
                }
            }
        }
    }

    // MARK: Moniteur

    func startMonitoring() {
        poll()
        poller?.invalidate()
        poller = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
    }

    func stopMonitoring() { poller?.invalidate(); poller = nil }

    private func poll() {
        guard state == .active else { return }
        if connection == nil {
            let c = NSXPCConnection(machServiceName: Shared.machService, options: [])
            c.remoteObjectInterface = NSXPCInterface(with: FilterXPC.self)
            c.setCodeSigningRequirement(Shared.clientRequirement)
            c.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
            c.resume()
            connection = c
        }
        let proxy = connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in self?.connection?.invalidate(); self?.connection = nil }
        } as? FilterXPC
        proxy?.recentEvents(since: lastEvent) { data in
            guard let list = try? JSONDecoder().decode([FlowEvent].self, from: data), !list.isEmpty else { return }
            Task { @MainActor in
                self.lastEvent = list.map(\.date).max() ?? self.lastEvent
                self.events = Array((self.events + list).suffix(1500))
            }
        }
    }
}

extension FirewallController: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.state = .needsApproval }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            self.state = .installing
            self.saveConfiguration()
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in self.state = .failed(error.localizedDescription) }
    }
}

extension FirewallController {
    /// Essais : état et connexions fictifs pour les captures (`--capture --demo`).
    func demo(state: State, events: [FlowEvent]) { self.state = state; self.events = events }
}
