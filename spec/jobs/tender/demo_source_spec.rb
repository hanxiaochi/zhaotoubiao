require "rails_helper"

RSpec.describe "招标演示源全流程", type: :job do
  include AuthenticationHelpers

  it "通过真实适配器同步、重复去重，并产生截止提醒" do
    user = create_user(permissions: [ "tenders.manage" ])
    source = TenderSource.create!(name: "本地演示源", base_url: "https://example.test/demo", access_mode: "demo", authorized: true, active: true)
    expect { Tender::SyncSourceJob.perform_now(source.id) }.to change(TenderNotice, :count).by(2)
    expect { Tender::SyncSourceJob.perform_now(source.id) }.not_to change(TenderNotice, :count)
    expect { Tender::DeadlineReminderJob.perform_now }.to change(user.notifications, :count).by(1)
    expect(source.reload.last_synced_at).to be_present
  end
end
