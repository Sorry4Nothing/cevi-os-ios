import Foundation

/// L35: one portfolio (Ressort) with leader, deputy and notes.
@MainActor @Observable
final class CampPortfolioModel {
    let active: ActiveCamp
    let portfolioId: UUID
    private(set) var phase: CampPhase = .loading
    private(set) var portfolio: CampPortfolio?
    private(set) var notes: [CampPortfolioNote] = []
    private(set) var error: String?

    init(active: ActiveCamp, portfolioId: UUID) {
        self.active = active
        self.portfolioId = portfolioId
    }

    var canWriteNotes: Bool { CampTaskRights(role: active.role, readOnly: active.isReadOnly, personId: nil).canEdit }

    func setPreview(phase: CampPhase, portfolio: CampPortfolio?, notes: [CampPortfolioNote]) {
        self.phase = phase
        self.portfolio = portfolio
        self.notes = notes
    }

    func load() async {
        guard let client = active.client, let campId = active.camp?.id else { return }
        do {
            async let loadedPortfolio = client.campPortfolio(campId: campId, portfolioId: portfolioId)
            async let loadedNotes = client.campPortfolioNotes(campId: campId, portfolioId: portfolioId)
            let (newPortfolio, page) = try await (loadedPortfolio, loadedNotes)
            portfolio = newPortfolio
            notes = page.notes
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if portfolio == nil { phase = CampPhase(error: error) } else { self.error = CampPhase(error: error).failureText }
        }
    }

    /// Returns true if the note was saved.
    func addNote(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canWriteNotes, !trimmed.isEmpty, let client = active.client, let campId = active.camp?.id else { return false }
        do {
            let note = try await BusyState.shared.track { try await client.createCampPortfolioNote(campId: campId, portfolioId: portfolioId, text: trimmed) }
            notes.insert(note, at: 0)
            error = nil
            return true
        } catch let failure as APIError {
            error = CampRules.writeError(failure)
        } catch { self.error = APIError.network.displayText }
        return false
    }
}
