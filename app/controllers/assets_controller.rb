class AssetsController < ApplicationController
  before_action :set_project
  before_action :set_asset, only: %i[show edit update]

  def show
    authorize @asset
    prepare_review
  end

  def new
    @asset = @project.assets.new
    authorize @asset
  end

  def create
    @asset = @project.assets.new(asset_params.merge(updated_by: current_user))
    authorize @asset
    Asset.transaction do
      @asset.save!
      @asset.capture_version!(change_reason: change_reason, actor: current_user)
      Audit::Recorder.call(action: "asset.create", record: @asset)
    end
    redirect_to @project, notice: "资产记录已创建并保存首个版本。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @asset
    prepare_review
  end

  def update
    authorize @asset
    @asset.with_lock do
      authorize @asset
      before_data = @asset.attributes
      @asset.update!(asset_params.merge(updated_by: current_user))
      @asset.capture_version!(change_reason: change_reason, actor: current_user)
      Audit::Recorder.call(action: "asset.update", record: @asset, before_data: before_data)
    end
    redirect_to @project, notice: "资产记录已更新，历史版本已保留。"
  rescue ActiveRecord::RecordInvalid
    prepare_review
    render :edit, status: :unprocessable_content
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_asset
    @asset = @project.assets.find_by!(public_id: params[:id])
  end

  def asset_params
    params.require(:asset).permit(:asset_code, :name, :category, :address, :rights_no, :appraisal_org, :appraisal_value, :disposal_status, :source_reference, :description)
  end

  def change_reason
    value = params.require(:asset)[:change_reason]
    return value if value.is_a?(String) && value.strip.present?

    @asset.errors.add(:change_reason, "不能为空")
    raise ActiveRecord::RecordInvalid, @asset
  end

  def prepare_review
    @versions = @asset.asset_versions.includes(:changed_by).order(created_at: :desc, id: :desc).to_a
    @risk_flags = @asset.risk_flags
    @related_assets = @project.assets.where(public_id: @risk_flags.flat_map { |flag| flag["related_public_ids"] }).index_by(&:public_id)
  end
end
