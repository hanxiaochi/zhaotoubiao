require "rails_helper"

RSpec.describe "真实 AI 联调（仅合成资料）", type: :request do
  before do
    skip "设置 RUN_LIVE_AI=1 并配置 AI 环境变量后执行" unless ENV["RUN_LIVE_AI"] == "1"
  end

  it "三个业务任务通过真实供应商生成并走批准写回请求" do
    admin = create_user(admin: true, email: "synthetic-ai@example.test")
    project = create_project(owner: admin, code: "SYNTHETIC-AI", name: "合成测试项目，无真实客户资料")
    source_text = "合成招标文件，非真实采购。\n第一章 资格条件：须提供登记证明，真实性由人工核验。\n第二章 废标条款：超过截止时间提交的文件不予接受。\n第三章 时间节点：投标截止为2026年10月1日09:00，北京时间。\n第四章 评分标准：方案完整性20分。\n待办建议：核对登记证明，检查投标截止时间。"
    project.project_documents.create!(uploaded_by: admin, category: "tender", original_filename: "synthetic-tender.txt", ocr_text: source_text, ocr_status: "completed",
      file: { io: StringIO.new(source_text), filename: "synthetic-tender.txt", content_type: "text/plain" })
    sign_in(admin)
    records = {
      "claim_analysis" => project.claims.create!(created_by: admin, creditor_name: "合成债权人", claim_amount: 100, summary: "合成测试：无合同和付款证据。"),
      "bid_analysis" => project.bid_analyses.create!(criteria: [ "方案完整性 20 分" ], risks: [], outline: []),
      "draft_document" => project.generated_documents.create!(created_by: admin, kind: "bid_technical", title: "合成技术方案", content: "范围：整理合成资料，所有人员与证书待填写。")
    }
    records.each do |task_type, record|
      record.update!(bid_analysis: records.fetch("bid_analysis"), refresh_bid_basis: true) if task_type == "draft_document"
      run = AiRun.create!(project: project, record: record, requested_by: admin, task_type: task_type)
      Ai::RunJob.perform_now(run.id)
      expect(run.reload.status).to eq("pending_review"), "#{task_type}: #{run.output}"
      expect(JSON.parse(run.output)).to be_a(Hash)
      if task_type == "bid_analysis"
        data = JSON.parse(run.output)
        BidAnalysis::REVIEW_SECTIONS.each_key { |field| expect(data.fetch(field)).to be_an(Array) }
        expect(data.fetch("qualification_requirements").join).to include("登记证明")
        expect(data.fetch("disqualification_clauses")).not_to be_empty
        expect(data.fetch("time_nodes")).not_to be_empty
        expect(data.fetch("suggested_tasks")).not_to be_empty
      end
      expect(run.model).to eq(ENV.fetch("AI_MODEL"))
      post approve_ai_run_path(run), params: { review_note: "自动化验收：仅合成资料，验证批准请求及事务写回。" }
      expect(run.reload.status).to eq("approved"), "#{task_type} 未能应用"
      expect(run.reviewed_by).to eq(admin)
      expect(record.reload.status).not_to eq("approved")
      expect(record.bid_basis_current?).to be(true) if task_type == "draft_document"
      puts "LIVE_AI #{task_type}: approved-writeback; input=#{run.input_tokens}; output=#{run.output_tokens}"
    end
  end

  it "完整投标通过真实供应商逐项模拟并由人工批准保存独立结果" do
    admin = create_user(admin: true, email: "synthetic-simulation@example.test")
    project = create_project(owner: admin, code: "SYNTHETIC-SIM", name: "合成模拟审核，无客户资料")
    analysis = project.bid_analyses.create!(criteria: [ "服务计划", "质量检查" ])
    rules = [
      [ "服务计划", 60, "正文明确写出服务计划为收集、整理、交付三步得60分，缺一步扣20分。只评文本完整性，不核验实际履约。" ],
      [ "质量检查", 40, "正文明确写出逐项检查和问题清单得40分，只写出其中一个得20分，均未写出得0分。" ]
    ]
    rules.each do |criterion, maximum, rule|
      analysis.bid_scores.create!(updated_by: admin, criterion: criterion, maximum: maximum, awarded: 1,
        rationale: "合成原始人工分，AI不能覆盖", scoring_rule: rule, requires_evidence: false, evidence_exception: "只评方案文本")
    end
    content = "第一章 服务计划\n服务计划分为收集、整理、交付三步。\n第二章 质量检查\n我们对交付成果逐项检查，形成问题清单。\n全文结束。"
    document = project.generated_documents.create!(created_by: admin, kind: "bid_technical", title: "完整合成技术标", content: content)
    sign_in(admin)
    post bid_analysis_bid_simulations_path(analysis), params: { source_ref: "generated:#{document.public_id}", bid_simulation: { title: "真实接口合成验收", confirmed_complete: true } }
    simulation = analysis.bid_simulations.last!
    post ai_suggest_bid_simulation_path(simulation)
    run = simulation.ai_runs.last!
    Ai::RunJob.perform_now(run.id)
    expect(run.reload.status).to eq("pending_review"), "供应商没有返回待复核结果：#{run.output}"
    expect(run.model).to eq(ENV.fetch("AI_MODEL"))
    post approve_ai_run_path(run), params: { review_note: "自动化接口验收：核对合成原文和规则，非客户评标。" }
    expect(run.reload.status).to eq("approved"), "模型输出未通过安全应用校验：#{run.output}"
    expect(simulation.reload.status).to eq("reviewed")
    expect(simulation.total_score).to eq(100)
    expect(simulation.results.map { |row| row["criterion_id"] }).to match_array(analysis.bid_scores.pluck(:public_id))
    expect(analysis.bid_scores.sum(:awarded)).to eq(2)
    expect(document.reload.content).to eq(content)
    puts "LIVE_AI bid_simulation: approved-independent-result; score=#{simulation.total_score}; input=#{run.input_tokens}; output=#{run.output_tokens}"
  end
end
