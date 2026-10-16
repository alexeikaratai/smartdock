import Cocoa
import SwiftUI
import Testing

@testable import SmartDockCore
@testable import SmartDockUI

/// The form's promise: one control per `DockProperty`, every one of them on screen, and
/// an edit that reaches the host without anything being stored or applied.
///
/// Two guards, and the second is new since the form became SwiftUI:
/// - `control(for:)` switches exhaustively, so a new setting does not **compile** until
///   it is drawn — the same tripwire the AppKit form had;
/// - `layout` says where each setting goes, and the first test here fails if one is
///   missing from it. The old form had no such check: a property with a control but no
///   place in the layout would have compiled and never appeared.
///
/// What is **not** covered any more, and was: that each control reads and writes the same
/// property. The AppKit form kept a `FieldBinding` per property that a test could drive
/// through real controls; a SwiftUI `Binding` cannot be reached without a view-inspection
/// dependency, and this package has none by design. What stands in its place is that the
/// read and the write sit on one line inside `bind(_:_:)`, so a mismatch is visible at
/// the point it would be written.
@Suite("Dock profile form")
@MainActor
struct DockProfileFormContentTests {

    /// Every setting changed away from its default, so a property that fails to travel
    /// shows up as a difference rather than a coincidence.
    static let everythingChanged = DockConfiguration(
        autohide: true,
        position: .right,
        iconSize: DockConfiguration.pixelsToScale(72),
        magnification: true,
        magnificationSize: DockConfiguration.pixelsToScale(100),
        minimizeEffect: .scale,
        animatesLaunch: false,
        showsRecents: false,
        showsIndicators: false,
        minimizesToApplication: true,
        menuBarAutoHide: .always)

    /// The layout is the only thing that decides whether a setting is on screen. A new
    /// `DockProperty` compiles once `control(for:)` draws it — this is what makes sure
    /// the drawing is actually reached.
    @Test func everyDockPropertyIsPlacedInTheForm() {
        let placed = DockProfileFormContent.order

        #expect(
            Set(placed) == Set(DockProperty.allCases),
            """
            the form places \(placed.count) of \(DockProperty.allCases.count) settings — \
            missing \(Set(DockProperty.allCases).subtracting(placed))
            """)
        #expect(placed.count == Set(placed).count, "a setting is placed twice: \(placed)")
    }

    /// An edit reaches the host as a whole configuration, with nothing stored or applied
    /// on the way — the form holds no state of its own to go stale.
    @Test func aneditIsHandedOverWhole() {
        var received: [DockConfiguration] = []
        let form = DockProfileFormContent(configuration: DockConfiguration()) { received.append($0) }

        form.onEdit(Self.everythingChanged)

        #expect(received == [Self.everythingChanged])
    }

    /// Each position gets its own picture, and a selected one differs from an unselected
    /// one — selection is carried by the thumbnail itself, so two that drew the same
    /// would leave the chosen position unmarked.
    @Test(arguments: DockPosition.allCases)
    func everyPositionHasItsOwnThumbnail(position: DockPosition) {
        let drawn = PositionIcon.image(for: position, selected: false)
        let others = DockPosition.allCases.filter { $0 != position }
            .map { PositionIcon.image(for: $0, selected: false).tiffRepresentation }

        #expect(drawn.size == PositionIcon.size)
        #expect(
            !others.contains(drawn.tiffRepresentation),
            "\(position) draws the same picture as another position")
        #expect(
            PositionIcon.image(for: position, selected: true).tiffRepresentation
                != drawn.tiffRepresentation,
            "selected and unselected \(position) look the same")
    }
}
