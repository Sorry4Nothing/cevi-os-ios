/// Sammelt Seiten einer Cursor-Paginierung (neueste zuerst). `naechster` ist der Cursor für die nächste, ältere Seite;
/// `nil` heisst Ende.
nonisolated struct Seitenfolge<Element: Sendable>: Sendable {
    private(set) var eintraege: [Element] = []
    private(set) var naechster: String?
    private(set) var istAmEnde = false

    /// Hängt eine ältere Seite an. Danach steht `naechster` für die folgende Seite.
    mutating func anhaengen(_ seite: [Element], naechster: String?) {
        eintraege.append(contentsOf: seite)
        self.naechster = naechster
        istAmEnde = naechster == nil
    }
}
