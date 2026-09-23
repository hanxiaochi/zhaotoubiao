class UsersController < ApplicationController
  before_action :set_user, only: %i[show edit update]

  def index
    authorize User
    @users = User.includes(:department, :roles).order(status: :asc, name: :asc)
  end

  def show
    authorize @user
  end

  def new
    @user = User.new(status: "active")
    authorize @user
  end

  def create
    @user = User.new(user_params.except(:role_ids))
    authorize @user
    User.transaction do
      @user.save!
      @user.role_ids = permitted_role_ids
      Audit::Recorder.call(action: "user.create", record: @user, after_data: @user.attributes.merge("role_ids" => @user.role_ids))
    end
    redirect_to users_path, notice: "用户已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @user
  end

  def update
    authorize @user
    if @user == current_user && user_params[:status] == "disabled"
      @user.errors.add(:status, "不能停用当前登录账户")
      return render :edit, status: :unprocessable_content
    end

    attributes = user_params.except(:role_ids)
    attributes = attributes.except(:password, :password_confirmation) if attributes[:password].blank?
    # Serialize administrative removals so concurrent requests cannot remove the last admin.
    Role.find_by!(code: "admin").with_lock do
      @user.reload
      authorize @user
      before_data = @user.attributes.merge("role_ids" => @user.role_ids)
      @user.update!(attributes)
      @user.role_ids = permitted_role_ids if user_params.key?(:role_ids)
      unless User.active.joins(:roles).where(roles: { code: "admin" }).exists?
        @user.errors.add(:base, "必须保留至少一个启用的系统管理员")
        raise ActiveRecord::RecordInvalid, @user
      end
      Audit::Recorder.call(action: "user.update", record: @user, before_data: before_data, after_data: @user.attributes.merge("role_ids" => @user.role_ids))
    end
    redirect_to users_path, notice: "用户资料和角色已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_user
    @user = User.find_by!(public_id: params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email, :department_id, :status, :password, :password_confirmation, role_ids: [])
  end

  def permitted_role_ids
    Role.where(id: user_params[:role_ids]).pluck(:id)
  end
end
