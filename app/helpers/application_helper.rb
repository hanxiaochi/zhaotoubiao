module ApplicationHelper
  PROJECT_TYPE_LABELS = {
    "bankruptcy" => "破产管理",
    "tender_agency" => "招标代理",
    "bid" => "投标辅助",
    "engineering_audit" => "工程审计",
    "asset_appraisal" => "资产评估",
    "financial_audit" => "财务审计"
  }.freeze

  STATUS_LABELS = {
    "draft" => "草稿", "active" => "进行中", "reviewing" => "审核中",
    "completed" => "已完成", "archived" => "已归档", "received" => "已接收",
    "initial_review" => "初审中", "supplement_required" => "待补充",
    "substantive_review" => "实质审核", "pending_approval" => "待审批",
    "approved" => "已通过", "rejected" => "已驳回", "pending" => "待处理",
    "missing" => "缺失", "returned" => "已退还", "uploaded" => "已上传",
    "processing" => "处理中", "reviewed" => "已复核", "pending_review" => "待复核",
    "new" => "新信息", "tracking" => "跟进中", "applied" => "已报名", "ignored" => "已忽略",
    "expired" => "已截止", "queued" => "排队中", "running" => "运行中",
    "failed" => "失败", "unrated" => "未评级",
    "delayed" => "已延期", "cancelled" => "已取消", "partial" => "部分收款",
    "paid" => "已收清", "unpaid" => "未收款", "overpaid" => "超额收款",
    "verified" => "已查验", "disposing" => "处置中", "disposed" => "已处置"
  }.freeze

  CLAIM_TYPE_LABELS = {
    "unknown" => "待认定", "secured" => "有财产担保债权", "employee" => "职工债权",
    "tax" => "税款债权", "priority" => "优先债权", "ordinary" => "普通债权",
    "subordinated" => "劣后债权"
  }.freeze

  def project_type_label(value)
    PROJECT_TYPE_LABELS.fetch(value.to_s, value.to_s.presence || "—")
  end

  def status_label(value)
    STATUS_LABELS.fetch(value.to_s, value.to_s.presence || "—")
  end

  def ai_task_label(value)
    { "bid_analysis" => "投标评分点与风险分析", "claim_analysis" => "债权辅助分析",
      "draft_document" => "业务文稿起草", "bid_simulation" => "完整投标文件模拟审核",
      "document_summary" => "文件摘要" }.fetch(value.to_s, value.to_s)
  end

  def document_kind_label(value)
    GeneratedDocument::KINDS.fetch(value.to_s, value.to_s)
  end

  def document_category_label(value)
    { "intake" => "接管资料", "claim" => "债权材料", "working_paper" => "审计底稿",
      "tender" => "招标文件", "bid" => "投标文件", "contract" => "合同", "other" => "其他" }.fetch(value.to_s, value.to_s)
  end

  def membership_role_label(value)
    { "owner" => "项目负责人", "manager" => "项目经理", "member" => "项目成员",
      "lawyer" => "律师", "observer" => "观察者" }.fetch(value.to_s, value.to_s)
  end

  def claim_type_label(value)
    CLAIM_TYPE_LABELS.fetch(value.to_s, value.to_s.presence || "—")
  end

  def workflow_record_label(value)
    { "Project" => "项目", "Claim" => "债权", "ProjectDocument" => "来源文件",
      "BidAnalysis" => "投标分析", "GeneratedDocument" => "业务文稿" }.fetch(value.to_s, "业务对象")
  end

  def workflow_decision_label(value)
    { "approve" => "通过", "reject" => "驳回", "return" => "退回修改",
      "complete" => "完成", "comment" => "记录意见" }.fetch(value.to_s, "历史处理意见")
  end

  def status_badge(value)
    palette = case value.to_s
    when "active", "approved", "completed" then "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
    when "reviewing", "pending_approval", "substantive_review" then "bg-amber-50 text-amber-700 ring-amber-600/20"
    when "rejected", "supplement_required" then "bg-rose-50 text-rose-700 ring-rose-600/20"
    else "bg-slate-50 text-slate-600 ring-slate-500/20"
    end
    tag.span(status_label(value), class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset #{palette}")
  end

  def money(value, currency: "CNY")
    return "—" if value.nil?

    unit = currency == "CNY" ? "¥" : "#{currency} "
    "#{unit}#{number_with_delimiter(format('%.2f', value))}"
  end

  def nav_link(label, path, active: false)
    classes = active ? "bg-white/12 text-white" : "text-slate-300 hover:bg-white/8 hover:text-white"
    link_to label, path, class: "flex items-center rounded-xl px-3 py-2.5 text-sm font-medium transition #{classes}"
  end
end
