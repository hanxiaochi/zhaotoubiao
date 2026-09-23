require "rails_helper"
require Rails.root.join("lib/solid_queue_windows_hostname")

RSpec.describe SolidQueueWindowsHostname do
  it "preserves Unicode Windows machine names as valid UTF-8" do
    allow(ENV).to receive(:fetch).with("COMPUTERNAME").and_return("合成验收工作机")
    process = Class.new { prepend SolidQueueWindowsHostname }.new
    expect(process.hostname).to eq("合成验收工作机")
    expect(process.hostname.encoding).to eq(Encoding::UTF_8)
    expect(process.hostname).to be_valid_encoding
  end
end
