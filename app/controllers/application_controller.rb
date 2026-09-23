class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_context
  before_action :require_authentication

  helper_method :current_user

  rescue_from Pundit::NotAuthorizedError do
    redirect_back fallback_location: root_path, alert: "您没有执行此操作的权限。"
  end

  rescue_from ActiveRecord::RecordNotFound do
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end

  private

  def current_user
    Current.user
  end

  def set_current_context
    Current.user = User.active.find_by(id: session[:user_id])
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
  end

  def require_authentication
    return if current_user

    if User.exists?
      redirect_to new_session_path, alert: "请先登录。"
    else
      redirect_to new_setup_path
    end
  end

  def user_for_paper_trail
    current_user&.public_id
  end
end
