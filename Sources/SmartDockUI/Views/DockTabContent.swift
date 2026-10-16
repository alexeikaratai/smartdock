import SmartDockCore
import SwiftUI

// MARK: - Dock Tab

/// The Dock tab: the profile picker, the profile form, the Use Current / Discard / Apply
/// row, the refusal notice, Sync from System and the status line.
///
/// **One card**, not a grouped `Form`. The grouped style was tried and measured 858pt
/// against the window's 900pt maximum: the tab scrolled, Apply sat below the fold and
/// eleven settings turned into a long ribbon. That presentation belongs to a full-width
/// System Settings pane; this window is 420pt wide and is read at a glance.
///
/// Holds no logic. Every intent goes to `DockTabModel`, which forwards it to the host —
/// nothing is applied or stored here.
struct DockTabContent: View {

    @Bindable var model: DockTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            card
            Button("Sync from System") { model.syncFromSystem() }
                .controlSize(.small)
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// No card around the form: the form draws its own, the way the General tab does,
    /// and a card inside a card was 190pt of padding when it was tried.
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Names what the control below actually does. Without it the picker reads as
            // a mode switch for the app rather than a choice of which profile is being
            // edited.
            VStack(alignment: .leading, spacing: 6) {
                Text("EDITING PROFILE")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(DockTabModel.Mode.allCases) { mode in
                        profileTile(mode)
                    }
                }
            }

            DockProfileFormContent(configuration: model.configuration) { model.edit($0) }

            buttons
            refusal
        }
    }

    /// One tile per profile. **Two facts, two ways of showing them**: the border and
    /// tint say which profile is being edited, a checkmark beside the name says which one
    /// the displays have put in force. They used to share a single string — a ● glued in
    /// front of the name inside a segmented control — and a person could not tell at a
    /// glance whether the profile they were editing was the one that would apply.
    private func profileTile(_ mode: DockTabModel.Mode) -> some View {
        let isSelected = model.selectedMode == mode
        return Button {
            model.requestMode(mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                HStack(spacing: 4) {
                    // A checkmark, because that is already what this app means by "in
                    // force": the menu marks the same profile with `state = .on`, which
                    // AppKit draws as one. An "Active now" line said the same thing in a
                    // second language, and cost a third row the other tile had to leave
                    // blank to stay level.
                    if model.isActive(mode) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(mode.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            model.isActive(mode) ? "\(mode.title), active now" : mode.title
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            // Fills the form from the Dock as it is right now. Deliberately applies
            // nothing: it seeds the fields and lights up Apply, so the change is still
            // the person's to confirm.
            Button("Use Current Dock") { model.useCurrentDock() }
            // Reloads the stored profile and drops the draft. Until it existed the only
            // way out of an experiment was to close the window, which threw the draft
            // away silently.
            Button("Discard") { model.discard() }
                .disabled(!model.isDirty)
            Button("Apply") { model.apply() }
                .disabled(!model.isDirty)
                .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .padding(.top, 2)
    }

    /// A setting macOS refused, shown right under the button that asked for it. Only
    /// while there is something to say, so a person never sees an empty orange gap.
    @ViewBuilder
    private var refusal: some View {
        if let notice = model.refusalNotice {
            Text("\u{26A0}\u{FE0F} \(notice)")
                .font(.caption)
                .foregroundStyle(Color.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

}
