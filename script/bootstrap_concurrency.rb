abort "Use the dedicated loopback bootstrap test database" unless Rails.env.test? && ApplicationRecord.connection_db_config.adapter == "postgresql" && ApplicationRecord.connection_db_config.host == "127.0.0.1" && ApplicationRecord.connection_db_config.database == "donghua_bootstrap_test"
abort "A fresh empty synthetic database is required" if User.exists? || Role.exists?
ready, gate = Queue.new, Queue.new
threads = Array.new(4) do |index|
  Thread.new do
    ApplicationRecord.connection_pool.with_connection do
      ready << true
      gate.pop
      begin
        SystemBootstrap.call(name: "Synthetic bootstrap #{index}", email: "synthetic-bootstrap-#{index}@example.test", password: SecureRandom.hex(24))
        :created
      rescue SystemBootstrap::AlreadyInitialized
        :prevented
      end
    end
  end
end
4.times { ready.pop }
4.times { gate << true }
results = threads.map(&:value)
raise "Concurrent bootstrap created multiple administrators" unless results.count(:created) == 1 && User.count == 1 && User.sole.admin? && Department.count == 3 && AuditEvent.where(action: "system.bootstrap").count == 1
puts({ concurrent_requests: 4, created_administrators: results.count(:created), prevented_requests: results.count(:prevented), departments: Department.count, roles: Role.count, bootstrap_audits: AuditEvent.where(action: "system.bootstrap").count }.to_json)
