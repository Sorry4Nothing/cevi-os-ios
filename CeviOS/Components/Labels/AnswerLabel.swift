import SwiftUI

/// "Noah kommt" with a symbol, so the state is readable without color.
struct AnswerLabel: View {
    let name: String
    let answer: Answer?

    var body: some View {
        switch answer {
        case .yes:
            Label("\(name) kommt", systemImage: "checkmark.circle.fill").foregroundStyle(Color.ceviOnSuccessContainer)
        case .no:
            Label("\(name) kommt nicht", systemImage: "xmark.circle.fill").foregroundStyle(Color.ceviOnErrorContainer)
        case nil:
            Label("Zusage für \(name) offen", systemImage: "circle.dashed").foregroundStyle(Color.ceviOnSurfaceVariant)
        }
    }
}
