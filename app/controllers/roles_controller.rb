class RolesController < ApplicationController
  before_action :set_role, only: %i[edit update]

  def index
    authorize Role
    @roles = Role.includes(:users).order(:name)
  end

  def new
    @role = Role.new(permissions: [])
    authorize @role
  end

  def create
    @role = Role.new(role_params)
    authorize @role
    Role.transaction do
      @role.save!
      Audit::Recorder.call(action: "role.create", record: @role)
    end
    redirect_to roles_path, notice: "角色已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @role
  end

  def update
    authorize @role
    @role.with_lock do
      authorize @role
      before_data = @role.attributes
      @role.update!(role_params)
      Audit::Recorder.call(action: "role.update", record: @role, before_data: before_data)
    end
    redirect_to roles_path, notice: "角色权限已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_role
    @role = Role.find(params[:id])
  end

  def role_params
    permitted = params.require(:role).permit(:code, :name, permissions: [])
    permitted[:permissions] = Array(permitted[:permissions]) & Role::AVAILABLE_PERMISSIONS.keys if permitted.key?(:permissions)
    permitted
  end
end
