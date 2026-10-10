cask "thunderaudio" do
  version "0.3.0"
  sha256 "f42ff43a9af289e8851ae11c9a526e034a34a2914ff134b7676c1aa17eb283d7"

  url "https://github.com/wwwwzzzzkkkk/ThunderAudio/releases/download/v#{version}/ThunderAudio-#{version}-macOS-arm64.zip"
  name "ThunderAudio"
  desc "System audio bridge between Macs over Thunderbolt networking or LAN"
  homepage "https://github.com/wwwwzzzzkkkk/ThunderAudio"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "ThunderAudio.app"

  caveats <<~EOS
    This developer build is ad-hoc signed and is not notarized.
    Use macOS Privacy & Security if macOS blocks opening it; do not disable Gatekeeper.
    Grant Screen & System Audio Recording permission on the sending Mac.
    Both Macs must run compatible versions. Quit ThunderAudio before upgrading.
  EOS
end
