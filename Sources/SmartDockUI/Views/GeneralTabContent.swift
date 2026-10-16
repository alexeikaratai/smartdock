import SwiftUI

// MARK: - General Tab

/// The General tab, in SwiftUI. Holds no logic of its own: every switch reads and writes
/// `GeneralSettingsModel`, which is where the behaviour is tested.
///
/// Switches rather than checkboxes, and a grouped `Form` rather than a column of
/// controls, because this window stands next to System Settings' own Dock pane and is
/// read against it. A binding is built by hand around each setter instead of binding
/// into a settable property: macOS can refuse a login item, so what the switch shows has
/// to be what the system reports afterwards, not what was asked for.
struct GeneralTabContent: View {

    let model: GeneralSettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at Login",
                    isOn: binding(\.launchesAtLogin, model.setLaunchAtLogin))
                Toggle(
                    "Notify on Profile Switch",
                    isOn: binding(\.notificationsEnabled, model.setNotifications))
                Toggle(
                    "Auto-import System changes",
                    isOn: binding(\.syncsFromSystem, model.setSyncFromSystem))
            } footer: {
                Text("Dock changes made in System Settings are copied into the active profile.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section {
                HStack {
                    Button("Refresh Now") { model.refreshNow() }
                    Button("Quit SmartDock") { model.quit() }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
    }

    /// One place where a read and its write sit side by side, for the same reason
    /// `DockProfileForm.binding(for:)` exists: two separate lists drift.
    private func binding(
        _ value: KeyPath<GeneralSettingsModel, Bool>,
        _ set: @escaping @MainActor (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(get: { model[keyPath: value] }, set: set)
    }
}
