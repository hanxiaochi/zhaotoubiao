class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]

  def new
    return redirect_to new_setup_path unless User.exists?
    redirect_to root_path if current_user
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    if user&.active? && user.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      user.update_column(:last_sign_in_at, Time.current)
      Current.user = user
      Audit::Recorder.call(action: "session.login", record: user)
      redirect_to root_path, notice: "欢迎回来，#{user.name}。"
    else
      flash.now[:alert] = "邮箱或密码不正确。"
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    user = current_user
    Audit::Recorder.call(action: "session.logout", record: user) if user
    reset_session
    redirect_to new_session_path, notice: "您已安全退出。"
  end
end
