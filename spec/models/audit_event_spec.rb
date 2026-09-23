require "rails_helper"

RSpec.describe AuditEvent, type: :model do
  it "在应用层禁止修改和删除" do
    event = AuditEvent.create!(action: "test.event", record_type: "Project", occurred_at: Time.current)

    expect(event.update(action: "tampered")).to be(false)
    expect(event.reload.action).to eq("test.event")
    expect(event.destroy).to be(false)
    expect(described_class.exists?(event.id)).to be(true)
  end
end
