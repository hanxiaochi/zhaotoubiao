module Workflow
  class DeadlineReminderJob < ApplicationJob
    queue_as :background

    WINDOW = 2.days

    def perform(reference_time = Time.current)
      tasks(reference_time).find_each do |task|
        task.pending_recipients.each do |recipient|
          next unless recipient.active? && ProjectPolicy.new(recipient, task.project).show?
          next unless create_notification(recipient, task, reference_time)
          Audit::Recorder.call(
          action: "workflow_task.deadline_reminded",
          record: task,
          after_data: { due_at: task.due_at, overdue: task.overdue?(reference_time), recipient_id: recipient.id }
          )
        end
      end
    end

    private

    def tasks(reference_time)
      WorkflowTask.current.where(status: %w[pending active], due_at: ..(reference_time + WINDOW))
    end

    def create_notification(user, task, reference_time)
      link = Rails.application.routes.url_helpers.workflow_task_path(task)
      Notification.deliver_once!(user: user, reference: task, date: reference_time.to_date,
        kind: "workflow.deadline",
        title: task.overdue?(reference_time) ? "审批任务已超时" : "审批任务即将到期",
        body: "#{task.project.name} · #{task.stage} · 截止 #{I18n.l(task.due_at, format: :short)}",
        link: link
      )
    end
  end
end
