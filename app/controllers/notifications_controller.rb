class NotificationsController < ApplicationController
  def index
    authorize Notification
    @notifications = policy_scope(Notification).order(created_at: :desc).limit(100)
  end

  def update
    notification = policy_scope(Notification).find_by!(public_id: params[:id])
    authorize notification
    notification.update!(read_at: Time.current)
    redirect_to notification.link.presence || notifications_path
  end
end
