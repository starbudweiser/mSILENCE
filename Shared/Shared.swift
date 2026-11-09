import Foundation

/// Constantes communes à l'appli et à l'extension réseau.
enum Shared {
    static let machService = "35KLMK53PN.fr.stephan.msilence.xpc"
    static let extensionID = "fr.stephan.msilence.extension"
    /// Clé de la liste de chemins bloqués dans `vendorConfiguration`.
    static let rulesKey = "blocked"
    /// Exigence de signature des deux côtés de la liaison XPC : Developer ID de mon équipe.
    static let clientRequirement = "anchor apple generic and certificate leaf[subject.OU] = \"35KLMK53PN\""
}

/// Une connexion vue par le filtre (affichée dans le moniteur).
struct FlowEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var appPath: String
    var host: String
    var port: String
    var proto: String      // TCP / UDP
    var blocked: Bool
}

@objc protocol FilterXPC {
    func recentEvents(since: Date, reply: @escaping (Data) -> Void)
}
