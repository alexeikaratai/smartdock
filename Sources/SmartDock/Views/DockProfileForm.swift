import Cocoa
import SmartDockCore

// MARK: - Dock Profile Form

/// The controls that edit one Dock profile — one per `DockProperty` — and nothing else:
/// no profile picker, no buttons, no status. The host reads and writes `configuration`
/// and hears `onEdited`.
///
/// Reading and writing used to be two lists in `SettingsWindow` — `populate(from:)`
/// assigning eight controls and `saveAndApply` reading eight controls back — the very
/// shape that let `toggleAutohide` silently drop settings. Here each field is declared
/// **once**, in `binding(for:)`, with its load and store side by side, and both
/// directions walk `DockProperty.allCases`. The switch is exhaustive on purpose: a new
/// `DockProperty` does not compile until this form has a control for it.
@MainActor
final class DockProfileForm: NSView {

    /// Fired on every edit, with nothing applied — the host decides what a draft means.
    var onEdited: (() -> Void)?

    private var positionPicker: PositionPicker!
    private var autohideCheckbox: NSButton!
    private var iconSizeSlider: NSSlider!
    private var iconSizeValueLabel: NSTextField!
    private var magnificationCheckbox: NSButton!
    private var magSizeSlider: NSSlider!
    private var magSizeValueLabel: NSTextField!
    private var minimizeEffectPopup: NSPopUpButton!
    private var animateCheckbox: NSButton!
    private var recentsCheckbox: NSButton!
    private var indicatorsCheckbox: NSButton!
    private var minimizeToAppCheckbox: NSButton!

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("DockProfileForm is built programmatically — init(coder:) is unavailable")
    }

    // MARK: - Configuration

    /// What the controls currently show. Setting it never fires `onEdited` — a load
    /// is not an edit.
    var configuration: DockConfiguration {
        get {
            DockProperty.allCases.reduce(DockConfiguration()) { config, property in
                binding(for: property).store(config)
            }
        }
        set {
            for property in DockProperty.allCases {
                binding(for: property).load(newValue)
            }
            reflectDependentState()
        }
    }

    // MARK: - Private

    /// One field's two directions: `load` shows a configuration in its control,
    /// `store` copies the control back into a configuration via `with(...)`.
    private struct FieldBinding {
        let load: (DockConfiguration) -> Void
        let store: (DockConfiguration) -> DockConfiguration
    }

    private func binding(for property: DockProperty) -> FieldBinding {
        switch property {
        case .position:
            FieldBinding(
                load: { self.positionPicker.selectedPosition = $0.position },
                store: { $0.with(position: self.positionPicker.selectedPosition) })
        case .autohide:
            FieldBinding(
                load: { self.autohideCheckbox.state = $0.autohide ? .on : .off },
                store: { $0.with(autohide: self.autohideCheckbox.state == .on) })
        case .iconSize:
            FieldBinding(
                load: { self.iconSizeSlider.doubleValue = $0.iconSize },
                store: { $0.with(iconSize: self.iconSizeSlider.doubleValue) })
        case .magnification:
            FieldBinding(
                load: { self.magnificationCheckbox.state = $0.magnification ? .on : .off },
                store: { $0.with(magnification: self.magnificationCheckbox.state == .on) })
        case .magnificationSize:
            FieldBinding(
                load: { self.magSizeSlider.doubleValue = $0.magnificationSize },
                store: { $0.with(magnificationSize: self.magSizeSlider.doubleValue) })
        case .minimizeEffect:
            FieldBinding(
                load: { self.minimizeEffectPopup.selectItem(withTitle: $0.minimizeEffect.displayName) },
                store: { $0.with(minimizeEffect: self.selectedMinimizeEffect) })
        case .animatesLaunch:
            FieldBinding(
                load: { self.animateCheckbox.state = $0.animatesLaunch ? .on : .off },
                store: { $0.with(animatesLaunch: self.animateCheckbox.state == .on) })
        case .showsRecents:
            FieldBinding(
                load: { self.recentsCheckbox.state = $0.showsRecents ? .on : .off },
                store: { $0.with(showsRecents: self.recentsCheckbox.state == .on) })
        case .showsIndicators:
            FieldBinding(
                load: { self.indicatorsCheckbox.state = $0.showsIndicators ? .on : .off },
                store: { $0.with(showsIndicators: self.indicatorsCheckbox.state == .on) })
        case .minimizesToApplication:
            FieldBinding(
                load: { self.minimizeToAppCheckbox.state = $0.minimizesToApplication ? .on : .off },
                store: { $0.with(minimizesToApplication: self.minimizeToAppCheckbox.state == .on) })
        }
    }

    /// Resolves the popup back to a case by index rather than by title — the popup
    /// is populated from `allCases` in the same order, and matching on the displayed
    /// string would break the moment a name is reworded.
    private var selectedMinimizeEffect: MinimizeEffect {
        let index = minimizeEffectPopup.indexOfSelectedItem
        guard MinimizeEffect.allCases.indices.contains(index) else { return .genie }
        return MinimizeEffect.allCases[index]
    }

    /// State that follows other controls rather than a field of its own: the
    /// magnification slider is only meaningful while magnification is on, and the
    /// pixel labels follow the sliders.
    private func reflectDependentState() {
        magSizeSlider.isEnabled = magnificationCheckbox.state == .on
        iconSizeValueLabel.stringValue = "\(DockConfiguration.scaleToPixels(iconSizeSlider.doubleValue)) px"
        magSizeValueLabel.stringValue = "\(DockConfiguration.scaleToPixels(magSizeSlider.doubleValue)) px"
    }

    // MARK: - Actions

    @objc private func controlChanged(_ sender: Any) {
        reflectDependentState()
        onEdited?()
    }

    // MARK: - UI

    private func buildUI() {
        let posLabel = UI.label("Dock Position", font: .systemFont(ofSize: 13, weight: .medium))
        addSubview(posLabel)

        positionPicker = PositionPicker()
        positionPicker.onSelectionChange = { [weak self] _ in self?.onEdited?() }
        addSubview(positionPicker)

        autohideCheckbox = UI.checkbox("Auto-hide Dock", target: self, action: #selector(controlChanged))
        addSubview(autohideCheckbox)

        let sizeTitle = UI.label("Icon Size", font: .systemFont(ofSize: 13, weight: .medium))
        addSubview(sizeTitle)

        iconSizeSlider = UI.scaleSlider(value: 0.29, target: self, action: #selector(controlChanged))
        addSubview(iconSizeSlider)

        iconSizeValueLabel = makeValueLabel()
        addSubview(iconSizeValueLabel)

        magnificationCheckbox = UI.checkbox("Magnification", target: self, action: #selector(controlChanged))
        addSubview(magnificationCheckbox)

        let magTitle = UI.label("Magnification Size", font: .systemFont(ofSize: 13, weight: .medium))
        addSubview(magTitle)

        magSizeSlider = UI.scaleSlider(value: 0.43, target: self, action: #selector(controlChanged))
        addSubview(magSizeSlider)

        magSizeValueLabel = makeValueLabel()
        addSubview(magSizeValueLabel)

        let minimizeTitle = UI.label("Minimize Effect", font: .systemFont(ofSize: 13, weight: .medium))
        addSubview(minimizeTitle)

        // Only the two effects System Events exposes — the enum is the source of
        // the list, so a third case would appear here without touching this file.
        minimizeEffectPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        minimizeEffectPopup.translatesAutoresizingMaskIntoConstraints = false
        minimizeEffectPopup.addItems(withTitles: MinimizeEffect.allCases.map(\.displayName))
        minimizeEffectPopup.target = self
        minimizeEffectPopup.action = #selector(controlChanged)
        addSubview(minimizeEffectPopup)

        animateCheckbox = UI.checkbox(
            "Animate opening applications", target: self, action: #selector(controlChanged))
        addSubview(animateCheckbox)

        recentsCheckbox = UI.checkbox(
            "Show recent applications", target: self, action: #selector(controlChanged))
        addSubview(recentsCheckbox)

        indicatorsCheckbox = UI.checkbox(
            "Show indicators for open applications", target: self, action: #selector(controlChanged))
        addSubview(indicatorsCheckbox)

        minimizeToAppCheckbox = UI.checkbox(
            "Minimize windows into application icon", target: self, action: #selector(controlChanged))
        addSubview(minimizeToAppCheckbox)

        // The host places this view 14pt inside its card, so every control sits on
        // the form's own edges; the vertical rhythm is the one the card always had.
        NSLayoutConstraint.activate([
            posLabel.topAnchor.constraint(equalTo: topAnchor),
            posLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            positionPicker.topAnchor.constraint(equalTo: posLabel.bottomAnchor, constant: 10),
            positionPicker.leadingAnchor.constraint(equalTo: leadingAnchor),
            positionPicker.trailingAnchor.constraint(equalTo: trailingAnchor),
            positionPicker.heightAnchor.constraint(equalToConstant: PositionPicker.buttonHeight),

            autohideCheckbox.topAnchor.constraint(equalTo: positionPicker.bottomAnchor, constant: 14),
            autohideCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),

            sizeTitle.topAnchor.constraint(equalTo: autohideCheckbox.bottomAnchor, constant: 16),
            sizeTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            iconSizeValueLabel.centerYAnchor.constraint(equalTo: sizeTitle.centerYAnchor),
            iconSizeValueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconSizeValueLabel.widthAnchor.constraint(equalToConstant: 50),

            iconSizeSlider.topAnchor.constraint(equalTo: sizeTitle.bottomAnchor, constant: 6),
            iconSizeSlider.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconSizeSlider.trailingAnchor.constraint(equalTo: trailingAnchor),

            magnificationCheckbox.topAnchor.constraint(equalTo: iconSizeSlider.bottomAnchor, constant: 14),
            magnificationCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),

            magTitle.topAnchor.constraint(equalTo: magnificationCheckbox.bottomAnchor, constant: 12),
            magTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            magSizeValueLabel.centerYAnchor.constraint(equalTo: magTitle.centerYAnchor),
            magSizeValueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            magSizeValueLabel.widthAnchor.constraint(equalToConstant: 50),

            magSizeSlider.topAnchor.constraint(equalTo: magTitle.bottomAnchor, constant: 6),
            magSizeSlider.leadingAnchor.constraint(equalTo: leadingAnchor),
            magSizeSlider.trailingAnchor.constraint(equalTo: trailingAnchor),

            minimizeTitle.topAnchor.constraint(equalTo: magSizeSlider.bottomAnchor, constant: 16),
            minimizeTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            minimizeEffectPopup.centerYAnchor.constraint(equalTo: minimizeTitle.centerYAnchor),
            minimizeEffectPopup.trailingAnchor.constraint(equalTo: trailingAnchor),
            minimizeEffectPopup.leadingAnchor.constraint(
                greaterThanOrEqualTo: minimizeTitle.trailingAnchor, constant: 12),

            animateCheckbox.topAnchor.constraint(equalTo: minimizeTitle.bottomAnchor, constant: 14),
            animateCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),

            recentsCheckbox.topAnchor.constraint(equalTo: animateCheckbox.bottomAnchor, constant: 8),
            recentsCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),

            indicatorsCheckbox.topAnchor.constraint(equalTo: recentsCheckbox.bottomAnchor, constant: 8),
            indicatorsCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),

            minimizeToAppCheckbox.topAnchor.constraint(equalTo: indicatorsCheckbox.bottomAnchor, constant: 8),
            minimizeToAppCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            minimizeToAppCheckbox.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Shows the slider's value in pixels — the unit System Settings uses, so a size
    /// seen there can be matched without guessing at a thumb position.
    private func makeValueLabel() -> NSTextField {
        let label = UI.label("", font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }
}
