class BidAnalysesController < ApplicationController
  before_action :set_project, only: %i[new create]
  before_action :set_analysis, only: %i[show edit update review]

  def new
    @analysis = @project.bid_analyses.new(status: "draft")
    authorize @analysis
  end

  def create
    @analysis = @project.bid_analyses.new(status: "draft")
    authorize @analysis
    assign_analysis_fields(@analysis)
    BidAnalysis.transaction do
      @analysis.save!
      Audit::Recorder.call(action: "bid_analysis.create", record: @analysis)
    end
    redirect_to @analysis, notice: "投标分析已创建，当前结论为待人工复核草稿。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def show
    authorize @analysis
    @scoring = BidScoringReport.new(@analysis)
    @library_entries = policy_scope(LibraryEntry).where(status: "active").where("expires_on IS NULL OR expires_on >= ?", Date.current).order(:title)
    @ai_runs = AiRun.where(record: @analysis).order(created_at: :desc).limit(10)
  end

  def edit
    authorize @analysis
    populate_virtual_fields
  end

  def update
    authorize @analysis
    @analysis.with_lock do
      authorize @analysis
      before_data = @analysis.attributes
      assign_analysis_fields(@analysis)
      @analysis.assign_attributes(status: "draft", reviewed_by: nil, reviewed_at: nil, review_note: nil)
      @analysis.save!
      Audit::Recorder.call(action: "bid_analysis.update", record: @analysis, before_data: before_data)
    end
    redirect_to @analysis, notice: "分析草稿已更新，修改后需重新复核。"
  rescue ActiveRecord::RecordInvalid
    populate_virtual_fields
    render :edit, status: :unprocessable_content
  end

  def review
    authorize @analysis, :review?
    @analysis.with_lock do
      authorize @analysis, :review?
      report = BidScoringReport.new(@analysis)
      if report.rows.any? && !report.ready?
        return redirect_to @analysis, alert: "评分尚未满足复核条件：#{report.issues.join('；')}"
      end
      before_data = @analysis.attributes
      @analysis.update!(status: "reviewed", reviewed_by: current_user, reviewed_at: Time.current, review_note: params.require(:review_note))
      Audit::Recorder.call(action: "bid_analysis.review", record: @analysis, before_data: before_data)
    end
    redirect_to @analysis, notice: "投标分析已由人工复核确认。"
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    redirect_to @analysis, alert: "请填写有效的人工复核依据。"
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_analysis
    @analysis = BidAnalysis.find_by!(public_id: params[:id])
  end

  def analysis_params
    params.require(:bid_analysis).permit(:simulated_score, *BidAnalysis::TEXT_FIELDS.map { |field| "#{field}_text" })
  end

  def assign_analysis_fields(record)
    values = analysis_params
    BidAnalysis::TEXT_FIELDS.each do |field|
      key = "#{field}_text"
      record.public_send("#{field}=", split_lines(values[key])) if values.key?(key)
    end
    record.simulated_score = values[:simulated_score]
  end

  def populate_virtual_fields
    BidAnalysis::TEXT_FIELDS.each { |field| @analysis.public_send("#{field}_text=", @analysis.public_send(field).join("\n")) }
  end

  def split_lines(value)
    value.to_s.lines.map(&:strip).reject(&:blank?)
  end
end
