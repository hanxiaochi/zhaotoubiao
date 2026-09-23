require "rails_helper"

RSpec.describe "Owner cloud synthetic fixtures" do
  let(:script) { Rails.root.join("deploy/owner-cloud/seed-demo.rb") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DEMO_DATA_ONLY").and_return("true")
    admin = User.create!(name: "Demo admin", email: "fixture-owner@example.test", password: "synthetic-only-password")
    admin.roles << Role.find_or_create_by!(code: "admin") { |role| role.name = "管理员" }
  end

  it "is repeatable without duplicate projects, fees or claims" do
    load script
    counts = [ Project.count, Fee.count, Asset.count, Claim.count ]
    load script
    expect([ Project.count, Fee.count, Asset.count, Claim.count ]).to eq(counts)
    expect(Project.where("code LIKE ?", "OWNER-DEMO-%").count).to eq(3)
    expect(Claim.last.status).to eq("received")
  end

  it "refuses a database without explicit synthetic-data opt-in" do
    allow(ENV).to receive(:[]).with("DEMO_DATA_ONLY").and_return(nil)
    expect { load script }.to raise_error(SystemExit)
    expect(Project.count).to eq(0)
  end

  it "does not overwrite an existing reserved project code" do
    project = Project.create!(code: "OWNER-DEMO-BANKRUPTCY", name: "Existing", project_type: "bankruptcy", status: "active")
    expect { load script }.to raise_error(SystemExit)
    expect(project.reload.name).to eq("Existing")
    expect(Fee.count).to eq(0)
  end
end
