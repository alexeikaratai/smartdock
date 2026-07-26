import Cocoa
import SmartDockCore

// MARK: - Position Picker

/// Horizontal picker with one icon-and-label button per `DockPosition`.
/// Owns its own selection highlighting; the host only reacts to `onSelectionChange`.
@MainActor
final class PositionPicker: NSStackView {

    /// Fired when the user picks a different position — not when `selectedPosition`
    /// is set programmatically while loading a profile.
    var onSelectionChange: ((DockPosition) -> Void)?

    /// Currently highlighted position. Setting it repaints the buttons.
    var selectedPosition: DockPosition = .bottom {
        didSet { updateSelection() }
    }

    static let buttonHeight: CGFloat = 60

    private var buttons: [DockPosition: NSButton] = [:]
    private var imageViews: [DockPosition: NSImageView] = [:]
    private var labels: [DockPosition: NSTextField] = [:]

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .horizontal
        spacing = 10
        distribution = .fillEqually

        for position in DockPosition.allCases {
            let button = makeButton(for: position)
            buttons[position] = button
            addArrangedSubview(button)
        }

        updateSelection()
    }

    required init?(coder: NSCoder) {
        fatalError("PositionPicker is built programmatically — init(coder:) is unavailable")
    }

    // MARK: - Private

    private func makeButton(for position: DockPosition) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.target = self
        button.action = #selector(buttonTapped(_:))
        button.tag = DockPosition.allCases.firstIndex(of: position) ?? 0

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = PositionIcon.image(for: position, selected: false)
        imageView.imageAlignment = .alignCenter
        button.addSubview(imageView)
        imageViews[position] = imageView

        let label = UI.label(position.displayName, font: .systemFont(ofSize: 10, weight: .medium))
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        button.addSubview(label)
        labels[position] = label

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: Self.buttonHeight),

            imageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
            imageView.widthAnchor.constraint(equalToConstant: PositionIcon.size.width),
            imageView.heightAnchor.constraint(equalToConstant: PositionIcon.size.height),

            label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
        ])

        return button
    }

    private func updateSelection() {
        for (position, button) in buttons {
            let isSelected = position == selectedPosition
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
                : NSColor.clear.cgColor
            imageViews[position]?.image = PositionIcon.image(for: position, selected: isSelected)
            labels[position]?.textColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        }
    }

    // MARK: - Actions

    @objc private func buttonTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < DockPosition.allCases.count else { return }

        selectedPosition = DockPosition.allCases[index]
        onSelectionChange?(selectedPosition)
    }
}
