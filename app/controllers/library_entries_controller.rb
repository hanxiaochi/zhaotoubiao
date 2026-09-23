class LibraryEntriesController < ApplicationController
  before_action :set_entry, only: %i[show edit update download]

  def index
    authorize LibraryEntry
    records = policy_scope(LibraryEntry)
    records = records.where(kind: params[:kind]) if params[:kind].present?
    records = records.where(status: params[:status]) if params[:status].present?
    if params[:q].present?
      query = "%#{LibraryEntry.sanitize_sql_like(params[:q])}%"
      records = records.where("title LIKE :q OR organization LIKE :q OR reference_number LIKE :q", q: query)
    end
    records = records.where("expires_on < ?", Date.current) if params[:expired] == "1"
    @total = records.count
    @page = [ params[:page].to_i, 1 ].max
    @entries = records.order(updated_at: :desc, id: :desc).offset((@page - 1) * 30).limit(30)
  end

  def show
    authorize @entry
  end

  def new
    @entry = LibraryEntry.new(kind: "qualification")
    authorize @entry
  end

  def create
    @entry = LibraryEntry.new(entry_params.merge(created_by: current_user))
    authorize @entry
    attach_uploads
    LibraryEntry.transaction do
      @entry.save!
      Audit::Recorder.call(action: "library.create", record: @entry)
    end
    redirect_to @entry, notice: "资料已入库。请由专业人员核对内容及授权范围。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @entry
  end

  def update
    authorize @entry
    @entry.with_lock do
      before_data = @entry.attributes
      @entry.assign_attributes(entry_params)
      @entry.revision_number += 1
      attach_uploads
      @entry.save!
      Audit::Recorder.call(action: "library.update", record: @entry, before_data: before_data)
    end
    redirect_to @entry, notice: "资料版本已更新；已引用的快照保持不变。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  def download
    authorize @entry, :download?
    attachment = @entry.documents.find(params[:attachment_id])
    Audit::Recorder.call(action: "library.download", record: @entry, after_data: { attachment_id: attachment.id })
    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.download, filename: attachment.filename.to_s, type: attachment.content_type, disposition: "attachment"
  end

  private

  def set_entry
    @entry = policy_scope(LibraryEntry).find_by!(public_id: params[:id])
  end

  def entry_params
    params.require(:library_entry).permit(:kind, :title, :organization, :reference_number, :description, :issued_on, :expires_on, :status)
  end

  def attach_uploads
    uploads = Array(params.require(:library_entry)[:documents]).reject(&:blank?)
    uploads.each do |upload|
      detected = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename)
      @entry.documents.attach(io: upload.tempfile, filename: File.basename(upload.original_filename), content_type: detected, identify: false)
    end
  end
end
