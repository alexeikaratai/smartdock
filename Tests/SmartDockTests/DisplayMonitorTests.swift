import CoreGraphics
import XCTest
@testable import SmartDockCore

@MainActor
final class DisplayMonitorTests: XCTestCase {

    // MARK: - Reconfiguration Flag Filtering

    /// Guards the raw values the filter relies on. `CGDisplayChangeSummaryFlags`
    /// has no documented stable ABI contract, so pin the four we depend on.
    func testTopologyFlagRawValues() {
        XCTAssertEqual(CGDisplayChangeSummaryFlags.beginConfigurationFlag.rawValue, 0x1)
        XCTAssertEqual(CGDisplayChangeSummaryFlags.addFlag.rawValue, 0x10)
        XCTAssertEqual(CGDisplayChangeSummaryFlags.removeFlag.rawValue, 0x20)
        XCTAssertEqual(CGDisplayChangeSummaryFlags.enabledFlag.rawValue, 0x100)
        XCTAssertEqual(CGDisplayChangeSummaryFlags.disabledFlag.rawValue, 0x200)
    }

    func testReactsToDisplayAdded() {
        XCTAssertTrue(shouldReactToDisplayChange(.addFlag))
    }

    func testReactsToDisplayRemoved() {
        XCTAssertTrue(shouldReactToDisplayChange(.removeFlag))
    }

    func testReactsToDisplayEnabled() {
        XCTAssertTrue(shouldReactToDisplayChange(.enabledFlag))
    }

    func testReactsToDisplayDisabled() {
        XCTAssertTrue(shouldReactToDisplayChange(.disabledFlag))
    }

    /// Mission Control and fullscreen transitions — must not re-apply dock config.
    func testIgnoresDesktopShapeChange() {
        XCTAssertFalse(shouldReactToDisplayChange(.desktopShapeChangedFlag))
    }

    /// Resolution change on an already-attached display.
    func testIgnoresModeChange() {
        XCTAssertFalse(shouldReactToDisplayChange(.setModeFlag))
    }

    /// Rearranging displays in System Settings.
    func testIgnoresMovedAndSetMain() {
        XCTAssertFalse(shouldReactToDisplayChange(.movedFlag))
        XCTAssertFalse(shouldReactToDisplayChange(.setMainFlag))
    }

    func testIgnoresMirroringChanges() {
        XCTAssertFalse(shouldReactToDisplayChange(.mirrorFlag))
        XCTAssertFalse(shouldReactToDisplayChange(.unMirrorFlag))
    }

    func testIgnoresEmptyFlags() {
        XCTAssertFalse(shouldReactToDisplayChange([]))
    }

    /// The begin-configuration pass is skipped even when it carries topology flags —
    /// we act on the completion callback that follows.
    func testIgnoresBeginConfigurationEvenWithTopologyFlags() {
        XCTAssertFalse(shouldReactToDisplayChange([.beginConfigurationFlag, .addFlag]))
        XCTAssertFalse(shouldReactToDisplayChange([.beginConfigurationFlag, .removeFlag]))
    }

    /// A real connect usually arrives bundled with layout noise — still a connect.
    func testReactsWhenTopologyFlagMixedWithNoise() {
        XCTAssertTrue(shouldReactToDisplayChange([.addFlag, .setModeFlag, .desktopShapeChangedFlag]))
        XCTAssertTrue(shouldReactToDisplayChange([.removeFlag, .movedFlag]))
    }

    // MARK: - Mock Behavior Validation

    func testMockDefaultsToNoExternal() {
        let monitor = MockDisplayMonitor()
        XCTAssertEqual(monitor.externalDisplayCount(), 0)
        XCTAssertFalse(monitor.hasExternalDisplay())
    }

    func testMockReportsExternalCorrectly() {
        let monitor = MockDisplayMonitor()
        monitor.mockExternalCount = 2
        XCTAssertEqual(monitor.externalDisplayCount(), 2)
        XCTAssertTrue(monitor.hasExternalDisplay())
    }

    func testMockCallbackFiresOnSimulation() {
        let monitor = MockDisplayMonitor()
        var callbackFired = false

        monitor.onConfigurationChanged = {
            callbackFired = true
        }

        monitor.simulateDisplayChange(externalCount: 1)
        XCTAssertTrue(callbackFired)
        XCTAssertEqual(monitor.externalDisplayCount(), 1)
    }

    func testMockTracksStartStopCalls() {
        let monitor = MockDisplayMonitor()
        XCTAssertEqual(monitor.startCallCount, 0)
        XCTAssertEqual(monitor.stopCallCount, 0)

        monitor.start()
        monitor.start()
        XCTAssertEqual(monitor.startCallCount, 2)

        monitor.stop()
        XCTAssertEqual(monitor.stopCallCount, 1)
    }

    // MARK: - Real DisplayMonitor (unit-safe checks)

    func testRealMonitorCanBeInstantiated() {
        let monitor = DisplayMonitor()
        XCTAssertNotNil(monitor)
    }

    func testRealMonitorReturnsNonNegativeCount() {
        let monitor = DisplayMonitor()
        // In CI/test environment can be 0 or more, but not negative
        XCTAssertGreaterThanOrEqual(monitor.externalDisplayCount(), 0)
    }

    func testRealMonitorStartStopDoesNotCrash() {
        let monitor = DisplayMonitor()
        monitor.start()
        monitor.stop()
        // Double stop should also not crash
        monitor.stop()
    }
}
