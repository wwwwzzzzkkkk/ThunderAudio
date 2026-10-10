cask "thunderaudio" do
  version "0.4.1"
  sha256 "dd858b855158521150b11798bc9bcf2d34d6bb6697e34daf5ddb0a26d7a23fa5"

  url "https://github.com/wwwwzzzzkkkk/ThunderAudio/releases/download/v#{version}/ThunderAudio-#{version}-macOS-arm64.zip"
  name "ThunderAudio"
  desc "System audio bridge between Macs over Thunderbolt networking or LAN"
  homepage "https://github.com/wwwwzzzzkkkk/ThunderAudio"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "ThunderAudio.app"

  caveats <<~EOS
    This developer build is ad-hoc signed and is not notarized.
    Use macOS Privacy & Security if macOS blocks opening it; do not disable Gatekeeper.
    Grant Screen & System Audio Recording permission on the sending Mac.
    Both Macs must run compatible versions. Quit ThunderAudio before upgrading.
  EOS
end
