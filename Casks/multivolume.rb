cask "multivolume" do
  version "1.1.1"
  sha256 "3a10d1bab3f63bd14cae3c53f2da7b63934272a3d4a677ecb728143f254e2c68"

  url "https://github.com/EcossAIah/MultiVolume/releases/download/v#{version}/MultiVolume-#{version}.zip"
  name "MultiVolume"
  desc "Menu bar volume control for aggregate and multi-output audio devices"
  homepage "https://github.com/EcossAIah/MultiVolume"

  depends_on macos: :sonoma

  app "MultiVolume.app"

  uninstall quit: "io.github.ecossaiah.multivolume"

  zap trash: "~/Library/Preferences/io.github.ecossaiah.multivolume.plist"

  caveats <<~EOS
    MultiVolume is not notarized, so macOS blocks the first launch.
    Open it once, then go to System Settings > Privacy & Security and click Open Anyway.
  EOS
end
