# Synthetic native PostgreSQL acceptance; never run this against a customer database.
abort "Production environment required" unless Rails.env.production?
databases = Rails.application.config.database_configuration.fetch("production")
expected = %w[primary queue cache cable]
connections = expected.to_h do |name|
  config = ActiveRecord::DatabaseConfigurations.new("production" => { name => databases.fetch(name) }).configs_for(env_name: "production", name: name)
  abort "Only loopback acceptance databases are allowed" unless config.adapter == "postgresql" && config.host == "127.0.0.1" && config.database.end_with?("_acceptance")
  [ name, config.database ]
end
abort "Databases must be independent" unless connections.values.uniq.size == 4
mode = ARGV.fetch(0, "inspect")

case mode
when "inspect"
  tables = {
    primary: ApplicationRecord.connection.tables,
    queue: SolidQueue::Record.connection.tables,
    cache: SolidCache::Record.connection.tables,
    cable: SolidCable::Record.connection.tables
  }
  raise "Primary contains background tables" if tables[:primary].any? { |table| table.start_with?("solid_") }
  { queue: "solid_queue_jobs", cache: "solid_cache_entries", cable: "solid_cable_messages" }.each do |name, table|
    raise "Missing isolated #{name} schema" unless tables[name].include?(table) && !tables[name].include?("projects")
  end
  Rails.cache.write("synthetic-acceptance", "persistent-cache", expires_in: 10.minutes)
  raise "Cache round trip failed" unless Rails.cache.read("synthetic-acceptance") == "persistent-cache"
  ActionCable.server.broadcast("synthetic-acceptance", { synthetic: true })
  raise "Cable persistence failed" unless SolidCable::Message.exists?
  puts({ databases: connections, table_counts: tables.transform_values(&:size), cache: "passed", cable: "passed" }.to_json)
when "enqueue"
  abort "Run enqueue only once in a fresh acceptance database" if Project.exists?(code: "PRODUCTION-ACCEPTANCE")
  user = User.create!(name: "Synthetic background acceptance", email: "production-acceptance@example.test", password: SecureRandom.hex(24), status: "active")
  project = Project.create!(owner: user, code: "PRODUCTION-ACCEPTANCE", name: "Synthetic native queue acceptance", project_type: "bankruptcy", status: "active")
  project.workflow_tasks.create!(record: project, assignee: user, stage: "Synthetic overdue review", due_at: 1.hour.ago)
  claim = project.claims.create!(created_by: user, creditor_name: "Synthetic recovery only", claim_amount: 100)
  run = AiRun.create!(project: project, record: claim, requested_by: user, task_type: "claim_analysis", status: "queued")
  run.update!(status: "running", updated_at: 16.minutes.ago)
  2.times { Workflow::DeadlineReminderJob.perform_later }
  Background::RecoverStaleJobsJob.perform_later
  raise "Jobs did not persist while workers are stopped" unless SolidQueue::ReadyExecution.count >= 3
  puts({ ready_jobs: SolidQueue::ReadyExecution.count, run_status: run.reload.status, notifications: user.notifications.count }.to_json)
when "check"
  project = Project.find_by!(code: "PRODUCTION-ACCEPTANCE")
  raise "Recovery did not persist" unless project.ai_runs.sole.status == "failed"
  notifications = project.owner.notifications.group(:kind).count
  raise "Reminder duplication or missing recovery" unless notifications == { "workflow.deadline" => 1, "background.recovery" => 1 }
  raise "Queue has failed executions" if SolidQueue::FailedExecution.exists?
  raise "Acceptance jobs are not finished" unless SolidQueue::Job.where(class_name: %w[Workflow::DeadlineReminderJob Background::RecoverStaleJobsJob]).where(finished_at: nil).none?
  puts({ recovery: "failed_and_notified", notifications: notifications, failed_jobs: 0, finished_jobs: SolidQueue::Job.where.not(finished_at: nil).count }.to_json)
else
  abort "Unknown mode; use inspect, enqueue or check"
end
