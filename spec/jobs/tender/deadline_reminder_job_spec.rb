require "rails_helper"

RSpec.describe Tender::DeadlineReminderJob, type: :job do
  include AuthenticationHelpers
  include ActiveSupport::Testing::TimeHelpers

  it "仅向有招标管理权限的人员发送七日内截止提醒并按日去重" do
    manager = create_user(email: "tender-reminder@example.com", permissions: [ "tenders.manage" ])
    create_user(email: "ordinary@example.com")
    source = TenderSource.create!(name: "授权源", base_url: "https://example.test/api", access_mode: "public_api", active: true, authorized: true)
    reference_time = Time.zone.parse("2026-09-03 08:00:00")
    travel_to reference_time
    notice = TenderNotice.create!(tender_source: source, title: "审计服务招标", url: "https://example.test/1", status: "new", deadline_at: reference_time + 3.days)

    expect { described_class.perform_now(reference_time) }.to change(manager.notifications, :count).by(1)
    expect { described_class.perform_now(reference_time + 1.hour) }.not_to change(manager.notifications, :count)
    expect(manager.notifications.last.link).to eq(Rails.application.routes.url_helpers.tender_notice_path(notice))
    expect(Notification.where(kind: "tender.deadline").count).to eq(1)
  end
end
