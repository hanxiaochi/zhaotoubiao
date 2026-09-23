class TenderSourcesController < ApplicationController
  before_action :set_source, only: %i[edit update sync]

  def index
    authorize TenderSource
    @sources = TenderSource.order(active: :desc, name: :asc)
  end

  def new
    @source = TenderSource.new(active: false, authorized: false, access_mode: "manual_import")
    authorize @source
  end

  def create
    @source = TenderSource.new(source_params)
    authorize @source
    TenderSource.transaction do
      @source.save!
      Audit::Recorder.call(action: "tender_source.create", record: @source)
    end
    redirect_to tender_sources_path, notice: "招标数据源已保存。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @source
  end

  def update
    authorize @source
    @source.with_lock do
      authorize @source
      before_data = @source.attributes
      @source.update!(source_params)
      Audit::Recorder.call(action: "tender_source.update", record: @source, before_data: before_data)
    end
    redirect_to tender_sources_path, notice: "数据源配置已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  def sync
    authorize @source, :update?
    return redirect_to(tender_sources_path, alert: "只有已授权、已启用的 API 数据源可以同步。") unless @source.syncable?

    Tender::SyncSourceJob.perform_later(@source.id)
    Audit::Recorder.call(action: "tender_source.sync_queued", record: @source)
    redirect_to tender_sources_path, notice: "数据源同步任务已进入队列。"
  end

  private

  def set_source
    @source = TenderSource.find_by!(public_id: params[:id])
  end

  def source_params
    params.require(:tender_source).permit(:name, :base_url, :access_mode, :active, :authorized, :credential_env_key)
  end
end
