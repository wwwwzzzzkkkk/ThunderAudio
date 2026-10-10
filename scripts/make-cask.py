#!/usr/bin/env python3
"""Generate a versioned Homebrew cask from the exact published archive."""
import argparse
import hashlib
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--repo", required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--archive", type=Path, required=True)
args = parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
    parser.error("invalid owner/repository")
if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
    parser.error("version must be X.Y.Z")
sha = hashlib.sha256(args.archive.read_bytes()).hexdigest()
Path("Casks").mkdir(exist_ok=True)
Path("Casks/thunderaudio.rb").write_text('''cask "thunderaudio" do
  version "%s"
  sha256 "%s"

  url "https://github.com/%s/releases/download/v#{version}/ThunderAudio-#{version}-macOS-arm64.zip"
  name "ThunderAudio"
  desc "System audio bridge between Macs over Thunderbolt networking or LAN"
  homepage "https://github.com/%s"

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
''' % (args.version, sha, args.repo, args.repo))
print(sha)
