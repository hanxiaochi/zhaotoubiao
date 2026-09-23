class SetupController < ApplicationController
  skip_before_action :require_authentication
  before_action :redirect_when_initialized

  def new
    @user = User.new
  end

  def create
    @user = SystemBootstrap.call(user_params.to_h)
    # Only authenticate after the complete bootstrap transaction commits.
    reset_session
    session[:user_id] = @user.id
    Current.user = @user
    redirect_to root_path, notice: "系统初始化完成，已创建管理员账户。"
  rescue SystemBootstrap::AlreadyInitialized
    redirect_to new_session_path, alert: "系统已由其他请求完成初始化，请使用管理员分配的账号登录。"
  rescue ActiveRecord::RecordInvalid => error
    @user = error.record.is_a?(User) ? error.record : User.new(user_params.except(:password, :password_confirmation))
    flash.now[:alert] = "初始化未完成，请核对输入或联系维护人员检查。"
    render :new, status: :unprocessable_content
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end

  def redirect_when_initialized
    redirect_to new_session_path if User.exists?
  end
end
