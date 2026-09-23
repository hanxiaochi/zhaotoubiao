require "rails_helper"

RSpec.describe "后台中断恢复与重复投递保护", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:claim) { project.claims.create!(created_by: admin, creditor_name: "恢复验收", claim_amount: 100) }
  before { sign_in(admin) }

  def document
    verify_claim_materials(claim)
    claim.claim_materials.first!.project_document.tap { |item| item.update!(content_type: "text/plain", ocr_status: "queued") }
  end

  def ai_run
    AiRun.create!(project: project, record: claim, requested_by: admin, task_type: "claim_analysis", status: "queued")
  end

  it "只恢复超时的运行和排队任务，保留正常与待人工复核任务，重复恢复不重复通知" do
    stale = ai_run
    stale.update!(status: "running", updated_at: 16.minutes.ago)
    fresh = ai_run
    review = ai_run
    review.update!(status: "pending_review", updated_at: 1.day.ago)
    source = document
    source.update!(ocr_status: "processing", ocr_attempt_token: "old", updated_at: 16.minutes.ago)
    expect { Background::RecoverStaleJobsJob.perform_now }.to change(Notification, :count).by(2)
    expect(stale.reload.status).to eq("failed")
    expect(fresh.reload.status).to eq("queued")
    expect(review.reload.status).to eq("pending_review")
    expect(source.reload.ocr_status).to eq("failed")
    expect(source.ocr_attempt_token).to be_nil
    expect { Background::RecoverStaleJobsJob.perform_now }.not_to change(Notification, :count)
    expect(AuditEvent.where(action: %w[ai_run.recovered_failed document.ocr_recovered_failed]).count).to eq(2)
  end

  it "AI 超时恢复后迟到的旧输出不能复活任务或覆盖新数据" do
    run = ai_run
    client = instance_double(Ai::OpenaiCompatibleClient, provider: "test", model: "test")
    allow(Ai::OpenaiCompatibleClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat) do
      run.reload.update!(updated_at: 16.minutes.ago)
      Background::RecoverStaleJobsJob.perform_now
      { content: '{"stale":"output"}' }
    end
    Ai::RunJob.perform_now(run.id)
    expect(run.reload.status).to eq("failed")
    expect(run.output).not_to include('"stale"')
    expect(run.raw_output).to be_blank
  end

  it "OCR 重复 Job 不重新提取，重复 HTTP 不再入队" do
    source = document
    expect { post analyze_project_project_document_path(project, source) }.not_to have_enqueued_job(Ocr::DocumentJob)
    Ocr::DocumentJob.perform_now(source.id)
    expect(source.reload.ocr_status).to eq("completed")
    source.update!(ocr_text: "人工保存的解析结果")
    Ocr::DocumentJob.perform_now(source.id)
    expect(source.reload.ocr_text).to eq("人工保存的解析结果")
  end

  it "OCR 旧轮次结果不覆盖超时恢复后新一轮任务" do
    source = document
    allow_any_instance_of(Ocr::DocumentJob).to receive(:extract) do
      source.reload.update!(updated_at: 16.minutes.ago)
      Background::RecoverStaleJobsJob.perform_now
      source.reload.update!(ocr_status: "processing", ocr_attempt_token: "replacement-token", ocr_text: "新一轮结果")
      { "text" => "迟到旧内容", "pages" => [] }
    end
    Ocr::DocumentJob.perform_now(source.id)
    expect(source.reload.ocr_text).to eq("新一轮结果")
    expect(source.ocr_attempt_token).to eq("replacement-token")
  end

  it "OCR 归档发生在执行期间时不写回迟到结果" do
    source = document
    allow_any_instance_of(Ocr::DocumentJob).to receive(:extract) do
      source.update!(status: "archived")
      { "text" => "不应写入", "pages" => [] }
    end
    Ocr::DocumentJob.perform_now(source.id)
    expect(source.reload.ocr_text).not_to eq("不应写入")
  end

  it "唯一索引阻止并发同键通知，日期和接收人有独立去重范围" do
    arguments = { user: admin, kind: "test.deadline", reference: claim, date: Date.current, title: "合成到期提醒" }
    first = Notification.deliver_once!(**arguments)
    expect(first).to be_persisted
    expect(Notification.deliver_once!(**arguments)).to be_nil
    expect(Notification.deliver_once!(**arguments.merge(date: Date.tomorrow))).to be_persisted
    expect(Notification.deliver_once!(**arguments.merge(user: create_user(email: "second-reminder@example.test")))).to be_persisted
    expect { Notification.create!(user: admin, kind: "other", title: "不能绕过索引", deduplication_key: first.deduplication_key) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
