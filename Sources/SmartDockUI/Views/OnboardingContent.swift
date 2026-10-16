import SwiftUI

// MARK: - Onboarding

/// The first-launch welcome: what SmartDock is, what it will and will not do, and one
/// button out.
///
/// The promise in the first bullet is load-bearing rather than decorative — on a fresh
/// install both profiles are the Dock exactly as it is, so nothing moves until a profile
/// is edited. An earlier version forced auto-hide on one profile and off on the other,
/// and the first thing the app did was move a Dock nobody had asked it to.
struct OnboardingContent: View {

    let appVersion: String
    let onGetStarted: () -> Void

    private static let features = [
        "Your Dock as it is becomes both profiles — nothing changes until you edit one",
        "Position, size, auto-hide, magnification per display setup",
        "Switch from the menu bar, a hotkey, a URL or a script",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("SmartDock")
                .padding(.top, 40)

            Text("SmartDock")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 12)

            Text("v\(appVersion) \u{00B7} by Alex Karatai")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(
                """
                SmartDock automatically adjusts your Dock settings when you connect or \
                disconnect an external monitor.
                """
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer(minLength: 24)

            Button("Get Started", action: onGetStarted)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
    }
}
