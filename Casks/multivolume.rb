cask "multivolume" do
  version "1.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/EcossAIah/MultiVolume/releases/download/v#{version}/MultiVolume-#{version}.zip"
  name "MultiVolume"
  desc "Menu bar volume control for aggregate and multi-output audio devices"
  homepage "https://github.com/EcossAIah/MultiVolume"

  depends_on macos: :sonoma

  app "MultiVolume.app"

  uninstall quit: "io.github.ecossaiah.multivolume"

  caveats <<~EOS
    MultiVolume is not notarized, so macOS blocks the first launch.
    Open it once, then go to System Settings > Privacy & Security and click Open Anyway.
  EOS
end
