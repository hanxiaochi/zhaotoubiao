require "digest"

class ProjectDocumentsController < ApplicationController
  MAX_FILE_SIZE = 50.megabytes
  ALLOWED_CONTENT_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/msword
    application/vnd.ms-excel
    image/jpeg image/png image/tiff text/plain text/csv
  ].freeze

  before_action :set_project
  before_action :set_document, only: %i[show download archive analyze]

  def new
    @project_document = @project.project_documents.new
    authorize @project_document
  end

  def create
    upload = document_params.delete(:file)
    @project_document = @project.project_documents.new(document_params.merge(uploaded_by: current_user))
    authorize @project_document
    validate_upload!(upload)
    return render_upload_errors if @project_document.errors.any?

    digest = Digest::SHA256.file(upload.tempfile.path).hexdigest
    detected_type = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename)
    @project_document.assign_attributes(
      original_filename: File.basename(upload.original_filename.to_s),
      content_type: detected_type,
      byte_size: upload.size,
      sha256: digest,
      ocr_status: ocr_candidate?(detected_type) ? "pending" : "not_required",
      analysis_status: "pending",
      metadata: { "client_content_type" => upload.content_type }
    )
    @project_document.file.attach(upload)
    ProjectDocument.transaction do
      @project_document.save!
      Audit::Recorder.call(action: "document.upload", record: @project_document)
    end
    respond_to do |format|
      format.html { redirect_to project_project_document_path(@project, @project_document), notice: "文件已安全上传并生成校验摘要。" }
      format.json { render json: { redirect_url: project_project_document_path(@project, @project_document) }, status: :created }
    end
  rescue ActiveRecord::RecordInvalid
    render_upload_errors
  end

  def show
    authorize @project_document
    respond_to do |format|
      format.html
      format.json { render json: { status: @project_document.ocr_status } }
    end
  end

  def download
    authorize @project_document, :download?
    Audit::Recorder.call(action: "document.download", record: @project_document)
    response.headers["Cache-Control"] = "private, no-store"
    send_data @project_document.file.download, filename: @project_document.original_filename,
      type: @project_document.content_type, disposition: "attachment"
  end

  def archive
    authorize @project_document, :archive?
    @project_document.with_lock do
      authorize @project_document, :archive?
      before_data = @project_document.attributes
      @project_document.update!(status: "archived", ocr_attempt_token: nil)
      Audit::Recorder.call(action: "document.archive", record: @project_document, before_data: before_data)
    end
    redirect_to @project, notice: "文件已归档，原始文件与审计记录仍保留。"
  end

  def analyze
    authorize @project_document, :update?
    supported_locally = @project_document.content_type.in?(%w[text/plain text/csv])
    unless supported_locally || Ocr::Client.configured?
      return redirect_to project_project_document_path(@project, @project_document), alert: "OCR 工作进程尚未配置；TXT/CSV 可直接提取，PDF 和图片需要 OCR_WORKER_URL。"
    end
    @project_document.with_lock do
      authorize @project_document, :update?
      if @project_document.ocr_status.in?(%w[queued processing])
        return redirect_to project_project_document_path(@project, @project_document), alert: "解析任务已在排队或运行，请勿重复提交。"
      end
      @project_document.update!(ocr_status: "queued", analysis_status: "queued", ocr_attempt_token: nil)
      Audit::Recorder.call(action: "document.ocr_queue", record: @project_document)
    end
    Ocr::DocumentJob.perform_later(@project_document.id)
    redirect_to project_project_document_path(@project, @project_document), notice: "文件解析任务已进入队列。"
  end

  private

  def render_upload_errors
    respond_to do |format|
      format.html { render :new, status: :unprocessable_content }
      format.json { render json: { errors: @project_document.errors.full_messages }, status: :unprocessable_content }
    end
  end

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_document
    @project_document = @project.project_documents.find_by!(public_id: params[:id])
  end

  def document_params
    params.require(:project_document).permit(:category, :file)
  end

  def validate_upload!(upload)
    if upload.blank?
      @project_document.errors.add(:file, "必须选择文件")
      return
    end
    @project_document.errors.add(:file, "不能超过 50 MB") if upload.size > MAX_FILE_SIZE
    detected_type = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename)
    @project_document.errors.add(:file, "类型不受支持") unless detected_type.in?(ALLOWED_CONTENT_TYPES)
  end

  def ocr_candidate?(content_type)
    content_type == "application/pdf" || content_type.start_with?("image/")
  end
end
