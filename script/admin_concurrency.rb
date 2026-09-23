# Use a NEW isolated database; the guard forbids touching existing business data.
abort "RAILS_ENV must be test" unless Rails.env.test?
config = ApplicationRecord.connection_db_config
abort "Use a fresh local admin concurrency PostgreSQL database" unless config.adapter == "postgresql" &&
  config.database.end_with?("_admin_concurrency_test") && config.configuration_hash[:host] == "127.0.0.1" && User.count.zero?

role = Role.create!(code: "admin", name: "Synthetic admin", permissions: [ "*" ])
password = SecureRandom.hex(24)
users = 2.times.map do |index|
  user = User.create!(name: "Synthetic admin #{index}", email: "admin#{index}@example.test", password: password, status: "active")
  user.roles << role
  user
end
sessions = users.map do |user|
  client = ActionDispatch::Integration::Session.new(Rails.application)
  client.post("/session", params: { email: user.email, password: password })
  raise "Synthetic login failed" unless client.response.status == 302
  client
end
ready, gate = Queue.new, Queue.new
workers = users.each_with_index.map do |user, index|
  Thread.new do
    ready << true
    gate.pop
    sessions[index].patch("/users/#{user.public_id}", params: { user: { role_ids: [ "" ] } })
    sessions[index].response.status
  end
end
2.times { ready.pop }
2.times { gate << true }
statuses = workers.map(&:value)
remaining = User.active.joins(:roles).where(roles: { code: "admin" }).count
raise "Last admin removal was not serialized" unless statuses.sort == [ 302, 422 ] && remaining == 1
raise "Rejected removal wrote an audit event" unless AuditEvent.where(action: "user.update").count == 1
puts({ requests: 2, statuses: statuses, remaining_admins: remaining, committed_updates: 1 }.to_json)
