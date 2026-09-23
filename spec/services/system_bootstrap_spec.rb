require "rails_helper"

RSpec.describe SystemBootstrap do
  let(:attributes) { { name: "合成初始化", email: "bootstrap@example.test", password: AuthenticationHelpers::TEST_PASSWORD } }

  it "checks initialization inside the transaction even when the caller passed an earlier empty check" do
    existing = User.create!(attributes)
    expect { described_class.call(attributes.merge(email: "second@example.test")) }.to raise_error(SystemBootstrap::AlreadyInitialized)
    expect(User.pluck(:id)).to eq([ existing.id ])
    expect(Role.count).to eq(0)
    expect(Department.count).to eq(0)
  end

  it "rolls back the admin, departments and roles if audit persistence fails" do
    allow(Audit::Recorder).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))
    expect { described_class.call(attributes) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(User.count).to eq(0)
    expect(Role.count).to eq(0)
    expect(Department.count).to eq(0)
    expect(Current.user).to be_nil
  end
end
