import SwiftUI

// MARK: - About Tab

/// The About tab, in SwiftUI: who this is, where to read about it, and the two things a
/// bug report needs. Holds no logic — every button calls `AboutModel`, which is where
/// the behaviour is tested.
struct AboutTabContent: View {

    let model: AboutModel

    var body: some View {
        VStack(spacing: 0) {
            identity
                .padding(.top, 40)

            HStack(spacing: 16) {
                Button("GitHub") { model.openRepository() }
                Button("Changelog") { model.openReleases() }
            }
            .padding(.top, 18)

            VStack(spacing: 8) {
                // The title carries the confirmation, because a modal for a clipboard
                // write would be heavy-handed. It goes back on its own, or a second bug
                // report gets filed from a button still claiming the first was copied.
                Button(model.hasCopied ? "Copied \u{2713}" : "Copy Diagnostic Info") {
                    model.copyDiagnostics()
                }
                Button(model.isCollectingLog ? "Collecting\u{2026}" : "Export Logs\u{2026}") {
                    Task { await model.exportLogs() }
                }
                .disabled(model.isCollectingLog)
            }
            .padding(.top, 10)

            Spacer(minLength: 20)

            Text("Made with \u{2764} by Alex Karatai")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var identity: some View {
        VStack(spacing: 2) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("SmartDock")
                .padding(.bottom, 8)

            Text("SmartDock")
                .font(.system(size: 18, weight: .semibold))

            Text("v\(model.appVersion) \u{00B7} by Alex Karatai")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("Automatically adjusts Dock settings for your display setup.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.top, 14)
        }
    }
}
