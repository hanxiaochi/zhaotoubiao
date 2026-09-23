class AiRunsController < ApplicationController
  TASK_RECORD_CLASSES = {
    "bid_analysis" => BidAnalysis,
    "claim_analysis" => Claim,
    "draft_document" => GeneratedDocument,
    "bid_simulation" => BidSimulation
  }.freeze

  before_action :set_run, only: %i[show approve reject]

  def create
    record, task_type = record_for_request
    run = AiRun.new(project: record.project, record: record, requested_by: current_user, task_type: task_type, status: "queued")
    authorize run
    unless Ai::OpenaiCompatibleClient.configured?
      return redirect_to record, alert: "AI 服务尚未配置。请在运行环境设置 AI_BASE_URL、AI_MODEL 和 AI_API_KEY。"
    end
    record.with_lock do
      authorize run
      if AiRun.where(record: record, task_type: task_type, status: %w[queued running pending_review]).exists?
        return redirect_to record, alert: "该对象已有进行中或待复核的 AI 任务。"
      end
      run.save!
      Audit::Recorder.call(action: "ai_run.create", record: run)
    end
    Ai::RunJob.perform_later(run.id)
    redirect_to run, notice: "AI 辅助任务已进入队列，输出必须人工复核后才能应用。"
  end

  def show
    authorize @run
    if @run.task_type == "bid_simulation" && @run.output.present? && @run.status.in?(%w[pending_review approved rejected])
      begin
        @simulation_preview = Ai::BidSimulationOutput.attributes_for(@run)
      rescue JSON::ParserError, KeyError, TypeError, ArgumentError => error
        @preview_error = "无法形成安全评分预览：#{error.message.to_s.first(160)}"
      end
    end
    respond_to do |format|
      format.html
      format.json { render json: { status: @run.status } }
    end
  end

  def approve
    authorize @run, :approve?
    review_note = params.require(:review_note)
    @run.record.with_lock do
      @run.with_lock do
        authorize @run, :approve?
        unless @run.source_current?
          return redirect_to @run, alert: "源数据已变更或该历史任务缺少版本指纹；请拒绝旧建议并重新生成，不能覆盖当前数据。"
        end
        apply_output!(@run)
        @run.update!(status: "approved", reviewed_by: current_user, reviewed_at: Time.current, review_note: review_note)
        Audit::Recorder.call(action: "ai_run.approve", record: @run, after_data: { task_type: @run.task_type, record_public_id: @run.record.try(:public_id) })
      end
    end
    notice = @run.task_type == "bid_simulation" ? "已保留独立模拟结果；人工自评分与文稿正文未改变。" : "AI 建议已由人工批准并应用到分析草稿。"
    redirect_to @run.record, notice: notice
  rescue JSON::ParserError, KeyError, TypeError, ArgumentError, ActiveRecord::RecordInvalid, ActionController::ParameterMissing => error
    redirect_to @run, alert: "AI 输出无法安全应用：#{error.message.to_s.first(160)}"
  end

  def reject
    authorize @run, :reject?
    @run.with_lock do
      authorize @run, :reject?
      @run.update!(status: "rejected", reviewed_by: current_user, reviewed_at: Time.current, review_note: params.require(:review_note))
      Audit::Recorder.call(action: "ai_run.reject", record: @run, after_data: { task_type: @run.task_type })
    end
    redirect_to @run.record, notice: "AI 建议已拒绝，业务数据未被修改。"
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    redirect_to @run, alert: "请填写有效的复核说明。"
  end

  private

  def set_run
    @run = AiRun.find_by!(public_id: params[:id])
  end

  def apply_output!(run)
    case run.task_type
    when "bid_analysis"
      data = output_object!(run)
      criteria = string_array!(data.fetch("criteria"), "criteria")
      risks = string_array!(data.fetch("risks"), "risks")
      outline = string_array!(data.fetch("outline"), "outline")
      sections = BidAnalysis::REVIEW_SECTIONS.keys.to_h do |field|
        # Legacy providers may omit new fields; do not erase existing manual sections.
        [ field, data.key?(field) ? string_array!(data.fetch(field), field) : run.record.public_send(field) ]
      end
      score = data["simulated_score"]
      score = Float(score) unless score.nil?
      raise TypeError, "simulated_score 超出 0-100" if score && !score.between?(0, 100)

      record = run.record
      before_data = record.attributes
      record.update!(**sections.symbolize_keys, criteria: criteria, risks: risks, outline: outline, simulated_score: score, status: "draft", reviewed_by: nil, reviewed_at: nil, review_note: nil)
      Audit::Recorder.call(action: "bid_analysis.ai_apply", record: record, before_data: before_data)
    when "claim_analysis"
      apply_claim_analysis!(run)
    when "draft_document"
      apply_draft_document!(run)
    when "bid_simulation"
      Ai::BidSimulationOutput.apply!(run)
    else
      raise KeyError, "不支持该任务类型"
    end
  end

  def string_array!(value, field)
    raise TypeError, "#{field} 必须是字符串数组" unless value.is_a?(Array) && value.all?(String)

    value.map(&:strip).reject(&:blank?)
  end

  def output_object!(run)
    value = JSON.parse(run.output)
    raise TypeError, "输出必须是 JSON 对象" unless value.is_a?(Hash)
    value
  end

  def output_string!(value, field)
    raise TypeError, "#{field} 必须是字符串" unless value.is_a?(String)
    value.strip
  end

  def record_for_request
    task_type = params[:task_type].to_s
    klass = TASK_RECORD_CLASSES[task_type]
    raise ActiveRecord::RecordNotFound, "不支持的 AI 任务类型" unless klass

    [ klass.find_by!(public_id: params[:id]), task_type ]
  end

  def apply_claim_analysis!(run)
    data = output_object!(run)
    recommended_type = data.fetch("recommended_type").to_s
    risk_level = data.fetch("risk_level").to_s
    raise TypeError, "recommended_type 不受支持" unless recommended_type.in?(Claim::CLAIM_TYPES)
    raise TypeError, "risk_level 不受支持" unless risk_level.in?(%w[low medium high critical unrated])

    analysis_data = {
      "analysis_summary" => output_string!(data.fetch("analysis_summary"), "analysis_summary"),
      "conflicts" => string_array!(data.fetch("conflicts"), "conflicts"),
      "legal_basis" => string_array!(data.fetch("legal_basis"), "legal_basis"),
      "missing_evidence" => string_array!(data.fetch("missing_evidence"), "missing_evidence"),
      "ai_run_public_id" => run.public_id,
      "evidence_refs" => run.evidence_refs
    }
    record = run.record
    before_data = record.attributes
    record.update!(recommended_type: recommended_type, risk_level: risk_level, analysis_data: analysis_data)
    Audit::Recorder.call(action: "claim.ai_apply", record: record, before_data: before_data)
  end

  def apply_draft_document!(run)
    data = output_object!(run)
    title = output_string!(data.fetch("title"), "title")
    content = output_string!(data.fetch("content"), "content")
    warnings = string_array!(data.fetch("warnings"), "warnings")
    raise TypeError, "title 不能为空" if title.blank?
    raise TypeError, "content 不能为空" if content.blank?

    record = run.record
    before_data = record.attributes
    record.update!(title: title, content: content, ai_warnings: warnings, status: "draft", approved_by: nil, approved_at: nil, review_note: nil)
    Audit::Recorder.call(action: "generated_document.ai_apply", record: record, before_data: before_data)
  end
end
