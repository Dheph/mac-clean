class MacClean < Formula
  desc "Interactive macOS cleanup tool — safely remove junk files and free disk space"
  homepage "https://github.com/Dheph/mac-clean"
  url "https://github.com/Dheph/mac-clean/archive/refs/heads/main.tar.gz"
  version "1.0.0"
  license "MIT"

  def install
    bin.install "mac-cleanup.sh" => "mac-clean"
  end

  def post_install
    ohai "macOS Cleanup Tool installed!"
    puts ""
    puts "  Run: mac-clean"
    puts ""
    puts "  For alias and scheduling setup: mac-clean setup"
    puts "  For help:                       mac-clean help"
  end

  test do
    assert_match "MAC CLEAN", shell_output("#{bin}/mac-clean help")
  end
end
