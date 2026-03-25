class Smartdock < Formula
  desc "Automatically toggle Dock visibility based on external monitors"
  homepage "https://github.com/alexkaratai/smartdock"
  url "https://github.com/alexkaratai/smartdock/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_ACTUAL_SHA256"
  license "MIT"

  depends_on :macos
  depends_on macos: :sonoma
  depends_on :xcode => ["16.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/SmartDock"

    # Generate icon and build .app bundle
    system "swift", "scripts/generate-icon.swift"

    app_dir = prefix/"SmartDock.app/Contents"
    (app_dir/"MacOS").mkpath
    (app_dir/"Resources").mkpath

    cp ".build/release/SmartDock", app_dir/"MacOS/SmartDock"
    cp "Resources/Info.plist", app_dir/"Info.plist"
    cp "Resources/AppIcon.icns", app_dir/"Resources/AppIcon.icns" if File.exist?("Resources/AppIcon.icns")
  end

  def post_install
    ohai "SmartDock needs Accessibility permission to control the Dock."
    ohai "Grant it in System Settings → Privacy & Security → Accessibility."
  end

  def caveats
    <<~EOS
      SmartDock lives in your menu bar (no Dock icon).
      After first launch, grant Accessibility permission in:
        System Settings → Privacy & Security → Accessibility
    EOS
  end

  test do
    system "swift", "test", "--parallel"
  end
end
