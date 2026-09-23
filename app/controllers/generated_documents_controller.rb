class GeneratedDocumentsController < ApplicationController
  before_action :set_project, only: %i[new create]
  before_action :set_document, only: %i[show edit update download_docx submit approve reject]

  def new
    template = TenderTemplate.where(active: true).find_by!(public_id: params[:template_id]) if params[:template_id].present?
    @document = @project.generated_documents.new(
      kind: params[:kind].presence || "general",
      title: template&.name,
      content: template ? Tender::TemplateRenderer.call(template: template, project: @project) : nil,
      status: "draft"
    )
    authorize @document
    if params[:bid_analysis_id].present?
      @document.bid_analysis = @project.bid_analyses.find_by!(public_id: params[:bid_analysis_id])
      @document.title ||= "#{@project.name} · 技术标草稿"
      @document.content ||= @document.bid_analysis.outline.map { |item| "#{item}\n【待填写：根据评分规则与真实证明材料编写】" }.join("\n\n").presence || "【待填写：根据评分规则与真实证明材料编写】"
    end
  end

  def create
    @document = @project.generated_documents.new(document_params.merge(created_by: current_user, status: "draft"))
    authorize @document
    GeneratedDocument.transaction do
      @document.save!
      Audit::Recorder.call(action: "generated_document.create", record: @document)
    end
    redirect_to @document, notice: "文稿草稿已保存。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def show
    authorize @document
    @ai_runs = @document.project.ai_runs.where(record: @document).order(created_at: :desc).limit(10)
  end

  def edit
    authorize @document
  end

  def update
    authorize @document
    @document.with_lock do
      authorize @document
      before_data = @document.attributes
      @document.update!(document_params.merge(status: "draft", approved_by: nil, approved_at: nil, review_note: nil))
      Audit::Recorder.call(action: "generated_document.update", record: @document, before_data: before_data)
    end
    redirect_to @document, notice: "文稿已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  def download_docx
    authorize @document, :show?
    Audit::Recorder.call(action: "generated_document.download_docx", record: @document, after_data: { status: @document.status })
    response.headers["Cache-Control"] = "private, no-store"
    send_data DocumentExport::DocxBuilder.call(@document),
      filename: "#{safe_filename(@document.title)}.docx",
      type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      disposition: "attachment"
  end

  def submit
    authorize @document, :submit?
    return unless transition!("pending_review", "generated_document.submit", review_note: nil)
    redirect_to @document, notice: "文稿已提交人工审批。"
  end

  def approve
    authorize @document, :approve?
    return unless transition!("approved", "generated_document.approve", approved_by: current_user, approved_at: Time.current, review_note: params[:review_note])
    redirect_to @document, notice: "文稿已审批通过。"
  end

  def reject
    authorize @document, :reject?
    return unless transition!("rejected", "generated_document.reject", approved_by: nil, approved_at: nil, review_note: params[:review_note])
    redirect_to @document, notice: "文稿已退回修改。"
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_document
    @document = GeneratedDocument.find_by!(public_id: params[:id])
  end

  def document_params
    attributes = params.require(:generated_document).permit(:kind, :title, :content, :refresh_bid_basis)
    if params[:generated_document].key?(:bid_analysis_public_id)
      public_id = params[:generated_document][:bid_analysis_public_id]
      project = @project || @document.project
      attributes[:bid_analysis] = public_id.present? ? project.bid_analyses.find_by!(public_id: public_id) : nil
    end
    attributes
  end

  def transition!(status, action, attributes = {})
    @document.with_lock do
      authorize @document, "#{action_name}?"
      before_data = @document.attributes
      @document.update!(attributes.merge(status: status))
      Audit::Recorder.call(action: action, record: @document, before_data: before_data)
    end
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing
    redirect_to @document, alert: @document.errors.full_messages.to_sentence.presence || "请填写有效审批意见。"
    false
  end

  def safe_filename(value)
    value.to_s.gsub(%r{[\\/:*?"<>|]}, "_").strip.first(80).presence || "业务文稿"
  end
end
