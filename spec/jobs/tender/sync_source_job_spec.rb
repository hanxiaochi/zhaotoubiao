require "rails_helper"

RSpec.describe Tender::SyncSourceJob, type: :job do
  it "按外部编号幂等同步授权 JSON 数据源并记录审计" do
    source = TenderSource.create!(name: "授权 JSON API", base_url: "https://example.test/notices", access_mode: "public_api", active: true, authorized: true)
    client = instance_double(Tender::SourceClient)
    allow(Tender::SourceClient).to receive(:new).with(source).and_return(client)
    allow(client).to receive(:fetch).and_return([
      { external_id: "N-001", title: "会计服务采购", url: "https://example.test/notices/1", region: "江苏", industry: "服务", published_at: Time.current, deadline_at: 5.days.from_now, tags: [ "审计" ] }
    ])

    expect { described_class.perform_now(source.id) }.to change(TenderNotice, :count).by(1)
    expect { described_class.perform_now(source.id) }.not_to change(TenderNotice, :count)

    notice = source.tender_notices.find_by!(external_id: "N-001")
    expect(notice.title).to eq("会计服务采购")
    expect(source.reload.last_synced_at).to be_present
    expect(AuditEvent.where(action: "tender_source.sync", record_id: source.id).count).to eq(2)
  end
end
