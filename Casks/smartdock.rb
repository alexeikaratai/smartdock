cask "smartdock" do
  version "1.0.0"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"

  url "https://github.com/alexkaratai/smartdock/releases/download/v#{version}/SmartDock-#{version}.dmg"
  name "SmartDock"
  desc "Automatically toggle Dock visibility based on external monitors"
  homepage "https://github.com/alexkaratai/smartdock"

  depends_on macos: ">= :sonoma"

  app "SmartDock.app"

  postflight do
    # Remind user about Accessibility permission
    ohai "SmartDock needs Accessibility permission to control the Dock."
    ohai "Grant it in System Settings → Privacy & Security → Accessibility."
  end

  zap trash: [
    "~/Library/Preferences/com.smartdock.app.plist",
    "~/Library/Caches/com.smartdock.app",
  ]
end
