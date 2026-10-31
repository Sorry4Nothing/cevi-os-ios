import SwiftUI

/// Leaders and unit leaders see no data without a device code.
struct DeviceCodeMissingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Geräte-Code einrichten")
                    .font(.title(.title1))
                    .foregroundStyle(Color.ceviOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Text("Als Leitung siehst du Daten von Kindern. Dafür braucht dein iPhone einen Geräte-Code. Ohne ihn zeigt Cevi OS nichts an.")
                Text("So richtest du ihn ein: Öffne die Einstellungen, tippe auf «Face ID & Code» (oder «Touch ID & Code») und dann auf «Code aktivieren». Danach öffnest du Cevi OS wieder.")
            }
            .foregroundStyle(Color.ceviOnSurfaceVariant)
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s8)
            .frame(maxWidth: Size.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .ceviScreenBackground()
    }
}
