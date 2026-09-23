class ClaimReviewRevision
  # Ordinary edits after approval cannot retain previous-stage approval. An explicit
  # supplement request is different: the responsible reviewer requested resubmission
  # to their own stage and receives a full new evidence snapshot on the next decision.
  def self.after_change!(claim)
    return if claim.review_stage == "initial" || claim.status == "supplement_required"
    previous_stage = claim.review_stage
    claim.update!(review_stage: "initial", status: "initial_review")
    Audit::Recorder.call(action: "claim.review_restarted", record: claim,
      after_data: { previous_stage: previous_stage, reason: "申报或核验依据发生修改，保留历史审核并回到经办初审" })
    ClaimReviewNotifier.call(claim)
  end

  def self.snapshot(claim)
    materials = claim.claim_materials.order(:id)
    {
      claim: claim.attributes,
      materials: materials.map(&:attributes),
      sources: ProjectDocument.where(id: materials.select(:project_document_id)).order(:id).map do |document|
        document.attributes.slice("id", "public_id", "original_filename", "sha256", "status", "updated_at")
      end,
      prerequisite_tasks: ClaimWorkflowGate.tasks(claim).map { |task| task.attributes.slice("id", "public_id", "status", "claim_basis_sha256") }
    }
  end
end
