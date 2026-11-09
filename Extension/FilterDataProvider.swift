import Foundation
import NetworkExtension
import Darwin

/// Filtre de contenu : coupe toute connexion sortante des applis bloquées (et de leurs processus enfants).
final class FilterDataProvider: NEFilterDataProvider {
    private var blocked: [String] = []
    private let lock = NSLock()
    private var events: [FlowEvent] = []
    private var listener: NSXPCListener?
    private var pathCache: [pid_t: (path: String, at: Date)] = [:]

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        loadRules()
        let any = NENetworkRule(remoteNetwork: nil, remotePrefix: 0, localNetwork: nil, localPrefix: 0, protocol: .any, direction: .outbound)
        let settings = NEFilterSettings(rules: [NEFilterRule(networkRule: any, action: .filterData)], defaultAction: .allow)
        apply(settings) { error in
            if error == nil { self.startXPC() }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        listener?.invalidate(); listener = nil
        completionHandler()
    }

    private func loadRules() {
        let conf = filterConfiguration.vendorConfiguration ?? [:]
        let list = (conf[Shared.rulesKey] as? [String]) ?? []
        lock.lock(); blocked = list; lock.unlock()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let sock = flow as? NEFilterSocketFlow else { return .allow() }
        var host = "", port = ""
        if let ep = sock.remoteEndpoint as? NWHostEndpoint { host = ep.hostname; port = ep.port }
        // Les échanges locaux restent permis, même pour une appli bloquée.
        if isLocal(host) { return .allow() }
        let pid = Self.pid(of: flow.sourceAppAuditToken)
        let isBlocked = pid != nil && matches(pid: pid!)
        record(pid: pid, host: host, port: port, proto: sock.socketType == SOCK_DGRAM ? "UDP" : "TCP", blocked: isBlocked)
        return isBlocked ? .drop() : .allow()
    }

    // MARK: Correspondance

    private func matches(pid: pid_t) -> Bool {
        lock.lock(); let rules = blocked; lock.unlock()
        if rules.isEmpty { return false }
        var cur = pid
        for _ in 0..<12 {                       // le processus puis ses parents
            if cur <= 1 { break }
            if let p = path(of: cur), rules.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return true }
            cur = Self.ppid(of: cur)
        }
        return false
    }

    private func path(of pid: pid_t) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let c = pathCache[pid], Date().timeIntervalSince(c.at) < 30 { return c.path }
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        let p = String(cString: buf)
        pathCache[pid] = (p, Date())
        if pathCache.count > 2000 { pathCache.removeAll() }
        return p
    }

    private static func pid(of token: Data?) -> pid_t? {
        guard let token, token.count == MemoryLayout<audit_token_t>.size else { return nil }
        return token.withUnsafeBytes { $0.load(as: audit_token_t.self) }.val.5.pidValue
    }

    private static func ppid(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return n > 0 ? pid_t(info.pbi_ppid) : 0
    }

    private func isLocal(_ h: String) -> Bool {
        h == "::1" || h == "localhost" || h.hasPrefix("127.") || h.hasPrefix("fe80:") || h == "0.0.0.0"
    }

    // MARK: Journal et XPC

    private func record(pid: pid_t?, host: String, port: String, proto: String, blocked: Bool) {
        let p = pid.flatMap { path(of: $0) } ?? "?"
        lock.lock()
        events.append(FlowEvent(date: Date(), appPath: p, host: host, port: port, proto: proto, blocked: blocked))
        if events.count > 1500 { events.removeFirst(events.count - 1000) }
        lock.unlock()
    }

    private func startXPC() {
        let l = NSXPCListener(machServiceName: Shared.machService)
        l.delegate = self
        l.setConnectionCodeSigningRequirement(Shared.clientRequirement)   // seule mon appli (équipe 35KLMK53PN) peut lire le journal
        l.resume()
        listener = l
    }
}

private extension UInt32 { var pidValue: pid_t { pid_t(bitPattern: self) } }

extension FilterDataProvider: NSXPCListenerDelegate, FilterXPC {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.exportedInterface = NSXPCInterface(with: FilterXPC.self)
        c.exportedObject = self
        c.resume()
        return true
    }

    func setBlocked(_ paths: [String], reply: @escaping () -> Void) {
        lock.lock(); blocked = paths; lock.unlock()
        reply()
    }

    func recentEvents(since: Date, reply: @escaping (Data) -> Void) {
        lock.lock(); let list = events.filter { $0.date > since }; lock.unlock()
        reply((try? JSONEncoder().encode(list)) ?? Data())
    }
}
