import SwiftUI

/// L37: «Mehr» of the camp view. Only entries whose target exists; the others follow with their slices (`docs/lager.md`).
struct CampMoreSheet: View {
    let profile: Profile
    let showAllCamps: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showsProfile = true } label: { row("Profil", symbol: "person.crop.circle") }
                }
                Section("Weiteres") {
                    Button { dismiss(); showAllCamps() } label: { row("Alle Lager", symbol: "tent") }
                }
                Section {} footer: { Text("Oben links wechselst du zurück zur Programm-Ansicht.") }
            }
            .scrollContentBackground(.hidden)
            .ceviScreenBackground()
            .navigationTitle("Mehr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schliessen", systemImage: "xmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showsProfile) { ProfileView(profile: profile) }
        }
    }

    private func row(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: symbol).foregroundStyle(Color.ceviAccent).frame(width: Size.touchTarget / 2).accessibilityHidden(true)
            Text(title).foregroundStyle(Color.ceviOnSurface)
            Spacer(minLength: Spacing.s2)
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(Color.ceviOnSurfaceVariant).accessibilityHidden(true)
        }
        .frame(minHeight: Size.touchTarget)
        .contentShape(.rect)
    }
}
