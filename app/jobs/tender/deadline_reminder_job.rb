module Tender
  class DeadlineReminderJob < ApplicationJob
    queue_as :background

    WINDOW_DAYS = 7

    def perform(reference_time = Time.current)
      recipients = User.active.includes(:roles).select { |user| user.allowed?("tenders.manage") }
      notices(reference_time).find_each do |notice|
        created = recipients.count { |user| create_notification(user, notice, reference_time) }
        Audit::Recorder.call(action: "tender_notice.deadline_reminded", record: notice, after_data: { recipients: created, deadline_at: notice.deadline_at }) if created.positive?
      end
    end

    private

    def notices(reference_time)
      TenderNotice.where(status: %w[new tracking], deadline_at: reference_time..(reference_time + WINDOW_DAYS.days))
    end

    def create_notification(user, notice, reference_time)
      link = Rails.application.routes.url_helpers.tender_notice_path(notice)
      Notification.deliver_once!(user: user, reference: notice, date: reference_time.to_date,
        kind: "tender.deadline",
        title: "招标项目即将截止",
        body: "#{notice.title} · 截止 #{I18n.l(notice.deadline_at, format: :short)}",
        link: link
      )
    end
  end
end
