require "rails_helper"

RSpec.describe Workflow::DeadlineReminderJob, type: :job do
  include AuthenticationHelpers

  it "超时任务按日去重提醒，已完成任务不再提醒" do
    user = create_user
    project = create_project(owner: user)
    task = project.workflow_tasks.create!(record: project, assignee: user, stage: "复核", due_at: 1.hour.ago)
    expect { described_class.perform_now }.to change(Notification, :count).by(1)
    expect(Notification.last.title).to eq("审批任务已超时")
    expect { described_class.perform_now }.not_to change(Notification, :count)
    task.update!(status: "approved")
    expect { described_class.perform_now(1.day.from_now) }.not_to change(Notification, :count)
  end
end
