import SmartDockCore
import SwiftUI

// MARK: - Dock Profile Form

/// One control per `DockProperty`, and nothing else: no profile picker, no buttons, no
/// status. The host hands over a `DockConfiguration` and hears every edit back as a new
/// one — this form stores nothing and applies nothing.
///
/// Laid out **compactly**, by hand, rather than as a grouped `Form`. The grouped style is
/// what System Settings uses and it reads well across a full-width pane, but this window
/// is 420pt wide: it came out 858pt tall against the window's 900pt maximum, so the tab
/// scrolled and Apply sat below the fold. One column of rows puts all eleven settings on
/// screen at once, which is what this window was always for.
///
/// Reading and writing used to be two lists in `SettingsWindow` — one assigning eight
/// controls, one reading eight controls back — the very shape that let `toggleAutohide`
/// silently drop settings. Each field is still declared **once**, in `control(for:)`,
/// with its load and store side by side in one `bind(_:_:)` call.
///
/// Two tripwires guard the set of settings:
/// - `control(for:)` switches **exhaustively** over `DockProperty`, so a new setting does
///   not compile until this form draws something for it;
/// - `order` is what actually gets drawn, and `everyDockPropertyIsPlacedInTheForm` fails
///   if a property is missing from it — a control nothing renders would otherwise compile
///   and never appear.
struct DockProfileFormContent: View {

    let configuration: DockConfiguration
    /// Fired on every edit, with nothing applied — the host decides what a draft means.
    let onEdit: (DockConfiguration) -> Void

    /// The order they are drawn in, which is also the whole set. Checked against
    /// `DockProperty.allCases` by a test.
    static let order: [DockProperty] = [
        .position, .autohide,
        .iconSize, .magnification, .magnificationSize,
        .minimizeEffect, .animatesLaunch, .showsRecents, .showsIndicators,
        .minimizesToApplication,
        .menuBarAutoHide,
    ]

    /// One inset card, and **no hairlines between the rows**. They were tried: a rule
    /// between every setting turned eleven of them into a ledger and added noise rather
    /// than structure, and the row spacing already separates them. Built by hand rather
    /// than with `.formStyle(.grouped)` because that style's own section padding is what
    /// measured 858pt here, against the window's 900pt maximum.
    var body: some View {
        VStack(spacing: 2) {
            ForEach(Self.order, id: \.self) { property in
                control(for: property)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Controls

    /// Exhaustive on purpose: a new `DockProperty` does not compile until it is drawn.
    @ViewBuilder
    private func control(for property: DockProperty) -> some View {
        switch property {
        case .position:
            positionRow(bind(\.position) { $0.with(position: $1) })

        case .autohide:
            switchRow("Auto-hide Dock", bind(\.autohide) { $0.with(autohide: $1) })

        case .iconSize:
            sizeRow("Icon Size", bind(\.iconSize) { $0.with(iconSize: $1) })

        case .magnification:
            switchRow("Magnification", bind(\.magnification) { $0.with(magnification: $1) })

        case .magnificationSize:
            sizeRow("Magnification Size", bind(\.magnificationSize) { $0.with(magnificationSize: $1) })
                // Only meaningful while magnification is on — the old form greyed the
                // slider out for the same reason.
                .disabled(!configuration.magnification)

        case .minimizeEffect:
            pickerRow("Minimize Effect", bind(\.minimizeEffect) { $0.with(minimizeEffect: $1) }) {
                ForEach(MinimizeEffect.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }

        case .animatesLaunch:
            switchRow("Animate opening applications", bind(\.animatesLaunch) { $0.with(animatesLaunch: $1) })

        case .showsRecents:
            switchRow("Show recent applications", bind(\.showsRecents) { $0.with(showsRecents: $1) })

        case .showsIndicators:
            switchRow(
                "Show indicators for open applications",
                bind(\.showsIndicators) { $0.with(showsIndicators: $1) })

        case .minimizesToApplication:
            switchRow(
                "Minimize windows into application icon",
                bind(\.minimizesToApplication) { $0.with(minimizesToApplication: $1) })

        case .menuBarAutoHide:
            // The same four positions System Settings offers, in its order — the enum is
            // the source of the list. It was a checkbox first, which could only reach two
            // of the four and read back the wrong one of them.
            pickerRow("Menu Bar", bind(\.menuBarAutoHide) { $0.with(menuBarAutoHide: $1) }) {
                ForEach(MenuBarAutoHide.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    // MARK: - Row shapes

    /// Three thumbnails with their names under them, which is how this control read
    /// before and the reason it was recognisable at a glance. Three small unlabelled
    /// segments in a trailing corner were not.
    private func positionRow(_ selection: Binding<DockPosition>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Dock Position")
            HStack(spacing: 0) {
                ForEach(DockPosition.allCases, id: \.self) { position in
                    positionButton(position, selection)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func positionButton(_ position: DockPosition, _ selection: Binding<DockPosition>)
        -> some View
    {
        let isSelected = selection.wrappedValue == position
        return Button {
            selection.wrappedValue = position
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: PositionIcon.image(for: position, selected: isSelected))
                    .frame(width: PositionIcon.size.width, height: PositionIcon.size.height)
                Text(position.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(position.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Label left, switch hard against the trailing edge. A `Toggle` left to itself
    /// hugs its own text, which puts the switch wherever the words happen to end and
    /// leaves a column of them staggered down the window.
    private func switchRow(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Toggle("", isOn: value)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    /// The value in **pixels** — the unit System Settings uses, so a size seen there can
    /// be matched without guessing at a thumb position.
    private func sizeRow(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                heading(title)
                Spacer()
                Text("\(DockConfiguration.scaleToPixels(value.wrappedValue)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
        }
    }

    private func pickerRow<Value: Hashable, Options: View>(
        _ title: String,
        _ value: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        HStack {
            heading(title)
            Spacer()
            Picker("", selection: value, content: options)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium))
    }

    // MARK: - Private

    /// One field's two directions in one place: where the value is read from and how it
    /// is written back. Two separate lists drift — that is the whole history of this file.
    private func bind<Value>(
        _ read: KeyPath<DockConfiguration, Value>,
        _ write: @escaping (DockConfiguration, Value) -> DockConfiguration
    ) -> Binding<Value> {
        Binding(
            get: { configuration[keyPath: read] },
            set: { onEdit(write(configuration, $0)) })
    }
}
