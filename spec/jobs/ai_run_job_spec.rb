require "rails_helper"

RSpec.describe Ai::RunJob, type: :job do
  it "保存 OpenAI-compatible 输出并进入待人工复核状态" do
    password = "SecurePass!2026"
    user = User.create!(name: "AI 测试员", email: "ai-job@example.com", password: password, password_confirmation: password, status: "active")
    project = Project.create!(code: "AI-001", name: "AI 测试项目", project_type: "bid", status: "active", owner: user)
    analysis = BidAnalysis.create!(project: project, status: "draft", criteria: [ "现有评分点" ], risks: [], outline: [])
    run = AiRun.create!(project: project, record: analysis, requested_by: user, task_type: "bid_analysis", status: "queued")
    client = instance_double(Ai::OpenaiCompatibleClient, provider: "test-provider", model: "test-model")
    allow(client).to receive(:chat).and_return(content: '{"criteria":["评分点A"],"risks":["风险A"],"outline":["提纲A"],"simulated_score":80}', input_tokens: 100, output_tokens: 50)
    allow(Ai::OpenaiCompatibleClient).to receive(:new).and_return(client)

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("pending_review")
    expect(run.provider).to eq("test-provider")
    expect(run.prompt_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(run.input_tokens).to eq(100)
  end
end
