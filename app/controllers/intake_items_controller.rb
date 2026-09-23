class IntakeItemsController < ApplicationController
  before_action :set_project
  before_action :set_intake_item, only: %i[show edit update download]

  def show
    authorize @intake_item
  end

  def new
    @intake_item = @project.intake_items.new(status: "pending")
    authorize @intake_item
  end

  def create
    @intake_item = @project.intake_items.new(intake_item_params.except(:attachments).merge(created_by: current_user))
    authorize @intake_item
    append_attachments
    IntakeItem.transaction do
      @intake_item.save!
      Audit::Recorder.call(action: "intake.create", record: @intake_item)
    end
    redirect_to @project, notice: "接管资料清单项已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @intake_item
  end

  def update
    authorize @intake_item
    @intake_item.with_lock do
      authorize @intake_item
      before_data = @intake_item.attributes
      @intake_item.assign_attributes(intake_item_params.except(:attachments))
      # Force a pending save before attaching so validation failure rolls back atomically.
      @intake_item.updated_at = Time.current
      append_attachments
      @intake_item.save!
      Audit::Recorder.call(action: "intake.update", record: @intake_item, before_data: before_data)
    end
    redirect_to @project, notice: "接管资料状态已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  def download
    authorize @intake_item, :show?
    attachment = @intake_item.attachments.find(params[:attachment_id])
    Audit::Recorder.call(action: "intake.download", record: @intake_item, after_data: { attachment_id: attachment.id })
    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type, disposition: "attachment"
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_intake_item
    @intake_item = @project.intake_items.find_by!(public_id: params[:id])
  end

  def intake_item_params
    params.require(:intake_item).permit(:category, :name, :status, :custodian, :received_at, :note, attachments: [])
  end

  def append_attachments
    Array(intake_item_params[:attachments]).reject(&:blank?).each do |upload|
      detected = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename)
      @intake_item.attachments.attach(io: upload.tempfile, filename: File.basename(upload.original_filename), content_type: detected, identify: false)
    end
  end
end
