class TenderNoticesController < ApplicationController
  before_action :set_notice, only: %i[show edit update]

  def index
    authorize TenderNotice
    @notices = policy_scope(TenderNotice).includes(:tender_source).order(published_at: :desc, created_at: :desc)
    @notices = @notices.where(region: params[:region]) if params[:region].present?
    @notices = @notices.where(industry: params[:industry]) if params[:industry].present?
    @notices = @notices.where(status: params[:status]) if params[:status].present?
  end

  def show
    authorize @notice
  end

  def new
    @notice = TenderNotice.new(status: "new", published_at: Time.current)
    authorize @notice
  end

  def edit
    authorize @notice
  end

  def create
    @notice = TenderNotice.new(notice_params)
    authorize @notice
    TenderNotice.transaction do
      @notice.save!
      Audit::Recorder.call(action: "tender_notice.create", record: @notice)
    end
    redirect_to @notice, notice: "招标信息已登记。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def update
    authorize @notice
    @notice.with_lock do
      authorize @notice
      before_data = @notice.attributes
      @notice.update!(notice_params)
      Audit::Recorder.call(action: "tender_notice.update", record: @notice, before_data: before_data)
    end
    redirect_to @notice, notice: "招标信息已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_notice
    @notice = TenderNotice.find_by!(public_id: params[:id])
  end

  def notice_params
    params.require(:tender_notice).permit(:tender_source_id, :external_id, :title, :url, :region, :industry, :published_at, :deadline_at, :status)
  end
end
