# Native development scheduling. Production uses the durable Solid Queue scheduler.
abort "Development scheduler only; use bin/jobs in production" unless Rails.env.development?
$stdout.sync = true
require "fileutils"
FileUtils.mkdir_p(Rails.root.join("tmp/pids"))
lock = File.open(Rails.root.join("tmp/pids/local_scheduler.lock"), "w")
abort "A local scheduler already owns this project" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
run_once = ENV["SCHEDULER_ONCE"] == "1"
last_sync = nil
loop do
  failed = false
  Rails.application.executor.wrap do
    [ Background::RecoverStaleJobsJob, Workflow::DeadlineReminderJob, Tender::DeadlineReminderJob ].each do |job|
      begin
        job.perform_now
      rescue StandardError => error
        warn "Local scheduler #{job.name} failed (#{error.class.name}); see task states and audit."
        failed = true
      end
    end
    if last_sync.nil? || Time.current - last_sync >= 30.minutes
      TenderSource.where(active: true, authorized: true).find_each do |source|
        next unless source.syncable?
        begin
          Tender::SyncSourceJob.perform_now(source.id)
        rescue StandardError => error
          warn "Local scheduler source #{source.public_id} failed (#{error.class.name}); see audit."
          failed = true
        end
      end
      last_sync = Time.current
    end
  end
  puts "Local scheduler tick complete at #{Time.current.iso8601}; failed=#{failed}"
  exit(failed ? 1 : 0) if run_once
  sleep 60
end
