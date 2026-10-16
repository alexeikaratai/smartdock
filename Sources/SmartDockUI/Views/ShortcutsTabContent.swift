import SmartDockCore
import SwiftUI

// MARK: - Shortcuts Tab

/// The Shortcuts tab: whether SmartDock is allowed to watch for global keystrokes, and
/// the five bindings.
///
/// The permission row is built in **both** states, and that is the point. It used to show
/// nothing once the permission was there — first as a hidden view, which still held
/// 133pt of blank because a hidden view keeps the height its contents ask for, then as no
/// view at all, which left the tab unable to say whether hotkeys could work.
struct ShortcutsTabContent: View {

    @Bindable var model: ShortcutsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(model.accessibility.settingName) { status }
                if !model.accessibility.isGranted {
                    grantRow
                }
            } footer: {
                if !model.accessibility.isGranted {
                    Text(
                        """
                        Grant Access restarts SmartDock and opens the list in System \
                        Settings — switch SmartDock on there. An entry left behind by an \
                        update is cleared on the way.
                        """
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
            }

            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.displayName) {
                        Button(model.title(for: action)) { model.record(action) }
                    }
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Click to record, Esc to clear.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private var status: some View {
        Label {
            Text(model.accessibility.isGranted ? "Allowed" : "Not allowed")
        } icon: {
            Image(
                systemName: model.accessibility.isGranted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(model.accessibility.isGranted ? Color.green : Color.yellow)
        }
    }

    /// One button, not two. *Open System Settings* and *Reset Permission* asked the
    /// person to know which of their two problems they had — never granted, or granted
    /// and then invalidated by an ad-hoc re-signing — when that difference is invisible
    /// from outside and the second fix works for both.
    private var grantRow: some View {
        HStack {
            Spacer()
            Button("Grant Access\u{2026}") { model.accessibility.grantAccess() }
        }
    }
}
