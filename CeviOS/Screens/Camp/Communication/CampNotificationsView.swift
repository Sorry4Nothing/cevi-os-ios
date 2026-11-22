import SwiftUI

/// Root of L19 inside a navigation stack; creates the model.
struct CampNotificationsView: View {
    @Environment(ActiveCamp.self) private var active
    @State private var model: CampNotificationsModel?

    var body: some View {
        Group { if let model { CampNotificationsScreen(model: model) } else { Color.clear } }
            .task {
                guard model == nil else { return }
                let created = CampNotificationsModel(active: active)
                model = created
                await created.load()
            }
    }
}

/// L19: tabs «Neu» and «Einstellungen».
struct CampNotificationsScreen: View {
    @Bindable var model: CampNotificationsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $model.tab) {
                Text(model.unread.isEmpty ? "Neu" : "Neu, \(model.unread.count)").tag(CampNotificationsModel.Tab.new)
                Text("Einstellungen").tag(CampNotificationsModel.Tab.settings)
            }
            .pickerStyle(.segmented).padding(.horizontal, Spacing.s4).padding(.bottom, Spacing.s2)
            switch model.tab {
            case .new:
                CampPhaseView(phase: model.phase, loading: "Benachrichtigungen werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.load() } }) {
                    CampScroll(staleSince: model.staleSince, error: model.error, refresh: { await model.load() }) { newList }
                }
            case .settings:
                CampPhaseView(phase: model.settingsPhase, loading: "Einstellungen werden geladen", back: .init(title: "Zurück") { dismiss() }, retry: { Task { await model.loadSettings() } }) {
                    CampScroll(error: model.error, refresh: { await model.loadSettings() }) { settingsList }
                }
            }
        }
        .ceviScreenBackground()
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.large)
        .task(id: model.tab) { if model.tab == .settings, model.settings.isEmpty { await model.loadSettings() } }
    }

    @ViewBuilder private var newList: some View {
        if model.entries.isEmpty {
            StateView(symbol: "bell", title: "Nichts Neues", message: "Zuteilungen, Erwähnungen und Fristen erscheinen hier.").frame(minHeight: 320)
        } else {
            if !model.unread.isEmpty {
                Button("Alle gelesen") { Task { await model.markAllRead() } }.buttonStyle(.ceviText).frame(minHeight: Size.touchTarget)
                VStack(spacing: 0) {
                    ForEach(model.unread) { row($0); if $0.id != model.unread.last?.id { Divider() } }
                }
                .ceviCard(padding: 0)
            }
            if !model.read.isEmpty {
                DisclosureGroup("Gelesen, \(model.read.count)") {
                    VStack(spacing: 0) { ForEach(model.read) { row($0); if $0.id != model.read.last?.id { Divider() } } }.ceviCard(padding: 0)
                }
                .font(.headline).foregroundStyle(Color.ceviOnSurfaceVariant).padding(.vertical, Spacing.s2)
            }
            Text("Pushes zeigen nie Nachrichtentext oder Namen von Kindern.").font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
        }
    }

    private func row(_ item: CampNotification) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: CampNotificationsModel.symbol(item.kind)).foregroundStyle(Color.ceviAccent).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(CampNotificationsModel.title(item.kind)).font(.headline).foregroundStyle(Color.ceviOnSurface)
                Text(CampNotificationsModel.message(item.kind)).foregroundStyle(Color.ceviOnSurface)
                Text(model.when(item.createdAt)).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
            }
            Spacer(minLength: Spacing.s2)
            if !item.isRead { Button("Gelesen") { Task { await model.markRead(item) } }.buttonStyle(.ceviText) }
        }
        .padding(Spacing.s3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(CampNotificationsModel.title(item.kind)). \(CampNotificationsModel.message(item.kind)) \(model.when(item.createdAt))\(item.isRead ? "" : ", ungelesen")"))
        .accessibilityAddTraits(item.isRead ? [] : .updatesFrequently)
        .accessibilityAction(named: Text("Als gelesen markieren")) { if !item.isRead { Task { await model.markRead(item) } } }
        .swipeActions { if !item.isRead { Button("Gelesen") { Task { await model.markRead(item) } } } }
    }

    @ViewBuilder private var settingsList: some View {
        Text("Die Schalter gelten für alle deine Lager. Eine abgeschaltete Art erzeugt weder Eintrag noch Push.").font(.subheadline).foregroundStyle(Color.ceviOnSurfaceVariant)
        VStack(spacing: 0) {
            ForEach(model.settings, id: \.kind) { setting in
                Toggle(isOn: .init(get: { setting.enabled }, set: { value in Task { await model.set(setting.kind, enabled: value) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CampNotificationsModel.title(setting.kind)).foregroundStyle(Color.ceviOnSurface)
                        Text(CampNotificationsModel.message(setting.kind)).font(.footnote).foregroundStyle(Color.ceviOnSurfaceVariant)
                    }
                }
                .frame(minHeight: Size.touchTarget).padding(.horizontal, Spacing.s3).padding(.vertical, Spacing.s1)
                if setting.kind != model.settings.last?.kind { Divider() }
            }
        }
        .ceviCard(padding: 0)
    }
}

#if DEBUG
#Preview("L19 Normal") { CampCommsPreview.notifications() }
#Preview("L19 Nacht") { CampCommsPreview.notifications().preferredColorScheme(.dark) }
#Preview("L19 Laden") { CampCommsPreview.notifications(phase: .loading) }
#Preview("L19 Leer") { CampCommsPreview.notifications(empty: true) }
#Preview("L19 Fehler") { CampCommsPreview.notifications(phase: .failed(state: nil, text: "x")) }
#Preview("L19 Einstellungen") { CampCommsPreview.notifications(tab: .settings) }
#Preview("L19 Einstellungen Nacht") { CampCommsPreview.notifications(tab: .settings).preferredColorScheme(.dark) }
#Preview("L19 Textgrösse AX3") { CampCommsPreview.notifications().dynamicTypeSize(.accessibility3) }
#endif
