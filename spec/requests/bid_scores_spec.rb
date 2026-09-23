require "rails_helper"

RSpec.describe "逐项投标模拟评分", type: :request do
  let!(:admin) { create_user(admin: true) }
  let!(:project) { create_project(owner: admin) }
  let!(:analysis) { project.bid_analyses.create!(status: "draft", criteria: [ "技术方案", "业绩" ]) }
  let!(:document) do
    project.project_documents.create!(uploaded_by: admin, category: "bid", original_filename: "proof.txt",
      file: { io: StringIO.new("合成原件"), filename: "proof.txt", content_type: "text/plain" })
  end
  before { sign_in(admin) }

  def score(criterion: "技术方案", maximum: 60, awarded: 50, **extra)
    post bid_analysis_bid_scores_path(analysis), params: {
      bid_score: { criterion: criterion, maximum: maximum, awarded: awarded, rationale: "按文件规则扣除未覆盖部分", project_document_id: document.id, page_reference: "第 2 页" }.merge(extra)
    }
  end

  it "逐项合计、评分覆盖及人工复核闭环，修改后旧复核失效" do
    score
    report = BidScoringReport.new(analysis)
    expect(report.awarded).to eq(50)
    expect(report.ready?).to be(false)
    post review_bid_analysis_path(analysis), params: { review_note: "不能提前通过" }
    expect(analysis.reload.status).to eq("draft")
    score(criterion: "业绩", maximum: 40, awarded: 32.5)
    report = BidScoringReport.new(analysis)
    expect(report.awarded).to eq(BigDecimal("82.5"))
    expect(report.maximum).to eq(100)
    expect(report.ready?).to be(true)
    post review_bid_analysis_path(analysis), params: { review_note: "已逐项核验" }
    expect(analysis.reload.status).to eq("reviewed")
    row = analysis.bid_scores.first!
    patch bid_analysis_bid_score_path(analysis, row), params: { bid_score: { awarded: 48 } }
    expect(analysis.reload.status).to eq("draft")
    expect(analysis.reviewed_at).to be_nil
    expect(BidScoringReport.new(analysis).awarded).to eq(BigDecimal("80.5"))
    expect(AuditEvent.where(action: "bid_score.update")).to exist
    get bid_analysis_path(analysis)
    expect(response.body).to include("80.50", "逐项自评分汇总")
  end

  it "拒绝负分、超分、非数字和无满分，不允许合计超过 100" do
    [ -1, 61, "NaN", "abc", nil ].each do |bad|
      expect { score(awarded: bad) }.not_to change(BidScore, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect { score(maximum: nil) }.not_to change(BidScore, :count)
    expect { score(maximum: "NaN") }.not_to change(BidScore, :count)
    expect { score(maximum: 0, awarded: 0) }.not_to change(BidScore, :count)
    score
    expect { score(criterion: "业绩", maximum: 50, awarded: 30) }.not_to change(BidScore, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect { score }.not_to change(BidScore, :count)
  end

  it "证据缺失可存草稿但不可复核；无需原件必须记录规则例外" do
    score(project_document_id: nil)
    expect(BidScoringReport.new(analysis).issues.join).to include("缺少同评分点")
    row = analysis.bid_scores.first!
    patch bid_analysis_bid_score_path(analysis, row), params: { bid_score: { requires_evidence: false, evidence_exception: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(row.reload.requires_evidence?).to be(true)
    patch bid_analysis_bid_score_path(analysis, row), params: { bid_score: { requires_evidence: false, evidence_exception: "招标文件该项只评价方案内容，不要求外部证明" } }
    expect(row.reload.evidence_issues).to be_empty
    expect(row.evidence_exception).to include("不要求外部证明")
  end

  it "资料库引用只有文字不能替代原件，失效来源不能支持复核" do
    source = LibraryEntry.create!(created_by: admin, kind: "case_study", title: "合成案例", organization: "测试", description: "文字说明")
    analysis.bid_evidences.create!(library_entry: source, created_by: admin, criterion: "技术方案", page_reference: "合同第 2 页", note: "已核验", source_snapshot: source.evidence_snapshot)
    score(project_document_id: nil)
    row = analysis.bid_scores.first!
    expect(row.evidence_issues).not_to be_empty
    source.documents.attach(io: StringIO.new("proof"), filename: "case.txt", content_type: "text/plain")
    analysis.bid_evidences.create!(library_entry: source, created_by: admin, criterion: "技术方案", page_reference: "原件第 2 页", note: "新增原件", source_snapshot: source.evidence_snapshot)
    expect(row.evidence_issues).to be_empty
    source.update!(expires_on: Date.current - 1)
    expect(row.evidence_issues).not_to be_empty
  end

  it "原件归档或缺页码产生问题提示，评分点变化保留旧记录且不计入总分" do
    score(page_reference: "")
    row = analysis.bid_scores.first!
    expect(row.evidence_issues).to include("原件位置或页码未填写")
    document.update!(status: "archived")
    expect(row.reload.evidence_issues.join).to include("已归档")
    analysis.update!(criteria: [ "新的评分点" ])
    report = BidScoringReport.new(analysis)
    expect(report.awarded).to eq(0)
    expect(report.issues.join).to include("评分点已变更")
    patch bid_analysis_bid_score_path(analysis, row), params: { bid_score: { active: false } }
    expect(response).to redirect_to(analysis)
    expect(row.reload.active?).to be(false)
  end

  it "不可跨项目关联文件、维护其他分析条目或由观察者写分" do
    other = create_project(owner: admin, code: "SCORE-OTHER")
    other_doc = other.project_documents.create!(uploaded_by: admin, category: "bid", original_filename: "other.txt",
      file: { io: StringIO.new("other"), filename: "other.txt", content_type: "text/plain" })
    expect { score(project_document_id: other_doc.id) }.not_to change(BidScore, :count)
    expect { score(project_document_id: 999_999_999) }.not_to change(BidScore, :count)
    score
    other_analysis = other.bid_analyses.create!(status: "draft", criteria: [ "技术方案" ])
    row = analysis.bid_scores.first!
    patch bid_analysis_bid_score_path(other_analysis, row), params: { bid_score: { awarded: 1 } }
    expect(response).to have_http_status(:not_found)
    observer = create_user(email: "score-observer@example.test")
    ProjectMembership.create!(project: project, user: observer, membership_role: "observer")
    delete session_path
    sign_in(observer)
    expect { score(criterion: "业绩", maximum: 40, awarded: 30) }.not_to change(BidScore, :count)
    get bid_analysis_path(analysis)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("登记评分</a>")
  end

  it "评分变更使旧 AI 建议指纹失效，数据库禁止绕过模型写入超分" do
    run = AiRun.create!(project: project, record: analysis, requested_by: admin, task_type: "bid_analysis", status: "pending_review")
    score
    expect(run.source_current?).to be(false)
    row = analysis.bid_scores.first!
    expect { BidScore.transaction(requires_new: true) { row.update_columns(awarded: 999) } }.to raise_error(ActiveRecord::StatementInvalid)
    expect(row.reload.awarded).to eq(50)
  end

  it "续期资料不自动让旧版原件重新有效" do
    source = LibraryEntry.create!(created_by: admin, kind: "qualification", title: "合成资质", organization: "测试", description: "原件", expires_on: Date.current - 1)
    source.documents.attach(io: StringIO.new("old proof"), filename: "old.txt", content_type: "text/plain")
    evidence = analysis.bid_evidences.create!(library_entry: source, created_by: admin, criterion: "技术方案", page_reference: "第 1 页", note: "历史引用", source_snapshot: source.evidence_snapshot)
    source.update!(expires_on: Date.current + 365, revision_number: 2)
    expect(evidence.usable_proof?).to be(false)
  end
end
