import Cocoa
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The form is the one place a profile is turned into controls and back. Until the
/// UI became a library these tests could not exist, and the only guard was the
/// exhaustive switch — which catches a *missing* field, not one whose load or store
/// quietly does the wrong thing.
@Suite("Dock profile form")
@MainActor
struct DockProfileFormTests {

    /// Every field off its default, so a binding that dropped one back to the
    /// default would show. The two sizes are anchored to `pixelsToScale` values
    /// that the sliders can hold exactly.
    private static let everythingChanged = DockConfiguration(
        autohide: true,
        position: .right,
        iconSize: DockConfiguration.pixelsToScale(72),
        magnification: true,
        magnificationSize: DockConfiguration.pixelsToScale(100),
        minimizeEffect: .scale,
        animatesLaunch: false,
        showsRecents: false,
        showsIndicators: false,
        minimizesToApplication: true)

    @Test func aConfigurationSurvivesTheRoundTrip() {
        let form = DockProfileForm()

        form.configuration = Self.everythingChanged

        #expect(form.configuration == Self.everythingChanged)
    }

    /// The other direction of the same guarantee: each property, alone, reaches the
    /// controls and comes back. Driven by `allCases` so a new property is covered
    /// the moment it compiles.
    @Test(arguments: DockProperty.allCases)
    func eachPropertyIsCarriedByItsControl(property: DockProperty) {
        let form = DockProfileForm()
        let base = DockConfiguration()
        let changed = Self.everythingChanged
        let single = flip(property, of: base, to: changed)

        form.configuration = single

        #expect(form.configuration == single, "\(property) did not survive the form")
        #expect(form.configuration != base, "\(property) reads back as the default")
    }

    /// Loading is not editing. The host marks the draft dirty on `onEdited`, so a
    /// load that fired it would light up Apply the moment a profile was shown.
    @Test func loadingDoesNotCountAsAnEdit() {
        let form = DockProfileForm()
        var edits = 0
        form.onEdited = { edits += 1 }

        form.configuration = Self.everythingChanged
        form.configuration = DockConfiguration()

        #expect(edits == 0)
    }

    // MARK: - Helpers

    /// `base` with one property taken from `other` — exhaustive, so a new property
    /// fails to compile here until the test knows how to isolate it.
    private func flip(_ property: DockProperty, of base: DockConfiguration, to other: DockConfiguration)
        -> DockConfiguration
    {
        switch property {
        case .position: base.with(position: other.position)
        case .autohide: base.with(autohide: other.autohide)
        case .iconSize: base.with(iconSize: other.iconSize)
        case .magnification: base.with(magnification: other.magnification)
        case .magnificationSize:
            // Only compared while magnification is on, so it travels with it.
            base.with(magnification: true, magnificationSize: other.magnificationSize)
        case .minimizeEffect: base.with(minimizeEffect: other.minimizeEffect)
        case .animatesLaunch: base.with(animatesLaunch: other.animatesLaunch)
        case .showsRecents: base.with(showsRecents: other.showsRecents)
        case .showsIndicators: base.with(showsIndicators: other.showsIndicators)
        case .minimizesToApplication: base.with(minimizesToApplication: other.minimizesToApplication)
        }
    }
}
