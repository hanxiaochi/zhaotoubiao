# Run only in a dedicated synthetic PostgreSQL test database, never the development/customer DB.
abort "RAILS_ENV must be test" unless Rails.env.test?
configuration = ApplicationRecord.connection_db_config
abort "Use a PostgreSQL database ending in _concurrency_test" unless configuration.adapter == "postgresql" && configuration.database.end_with?("_concurrency_test")

suffix = SecureRandom.hex(6)
user = User.create!(name: "Synthetic concurrency reviewer", email: "pg-#{suffix}@example.test", password: SecureRandom.hex(24), status: "active")
role = Role.find_or_create_by!(code: "admin") { |item| item.name = "Synthetic test admin"; item.permissions = [ "*" ] }
user.roles << role
project = Project.create!(owner: user, code: "PG-CONC-#{suffix}", name: "Synthetic concurrency only", project_type: "bankruptcy", status: "active")
claim = project.claims.create!(created_by: user, creditor_name: "Synthetic concurrency claim", claim_amount: 100)
document = project.project_documents.create!(uploaded_by: user, category: "claim", original_filename: "synthetic.txt", status: "uploaded", ocr_status: "not_required",
  sha256: Digest::SHA256.hexdigest("Synthetic evidence only"), byte_size: "Synthetic evidence only".bytesize, content_type: "text/plain",
  file: { io: StringIO.new("Synthetic evidence only"), filename: "synthetic.txt", content_type: "text/plain" })
claim.claim_materials.create!(material_type: "Synthetic evidence", present: true, project_document: document, checked_by: user,
  signature_requirement: "required", seal_requirement: "required", authorization_requirement: "required",
  signature_detected: true, seal_detected: true, authorization_complete: true)

def simultaneous(count)
  ready, gate = Queue.new, Queue.new
  threads = Array.new(count) do
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do
        ready << true
        gate.pop
        yield
      end
    end
  end
  count.times { ready.pop }
  count.times { gate << true }
  threads.map(&:value)
end

results = simultaneous(4) do
  current_claim = Claim.find(claim.id)
  begin
    current_claim.with_lock do
      transition = ClaimReviewFlow.new(current_claim, user).transition_for(stage: "initial", decision: "approve")
      current_claim.claim_reviews.create!(reviewer: user, stage: "initial", decision: "approve", comment: "Concurrent synthetic initial review",
        basis_sha256: ClaimWorkflowGate.basis(current_claim), evidence_snapshot: ClaimReviewRevision.snapshot(current_claim))
      current_claim.update!(transition)
    end
    :approved
  rescue ClaimReviewFlow::InvalidTransition
    :prevented
  end
end
raise "Concurrent review duplicated or skipped a stage" unless results.count(:approved) == 1 && claim.claim_reviews.count == 1 && claim.reload.review_stage == "professional"

deliveries = simultaneous(4) do
  Notification.deliver_once!(user: user, kind: "concurrency.acceptance", reference: claim, date: Date.current, title: "Synthetic concurrent reminder")
end
raise "Concurrent reminder duplicated" unless deliveries.compact.size == 1 && user.notifications.where(kind: "concurrency.acceptance").count == 1
puts({ adapter: configuration.adapter, concurrent_review_attempts: results.size, accepted_reviews: results.count(:approved), prevented_reviews: results.count(:prevented), reminder_attempts: deliveries.size, accepted_reminders: deliveries.compact.size }.to_json)
