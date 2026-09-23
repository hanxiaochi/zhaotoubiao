class ClaimWorkflowGate
  def self.basis(claim)
    materials = claim.claim_materials.order(:id)
    sources = ProjectDocument.where(id: materials.select(:project_document_id)).order(:id).map(&:attributes)
    payload = {
      claim: claim.attributes.except("updated_at", "completeness_score", "status"),
      materials: materials.map(&:attributes),
      sources: sources,
      supplements: claim.claim_supplements.order(:id).map(&:attributes)
    }
    Digest::SHA256.hexdigest(payload.to_json)
  end

  def self.tasks(claim)
    WorkflowTask.current.where(record: claim, claim_review_stage: claim.review_stage).order(:id)
  end

  def self.issues(claim)
    tasks(claim).filter_map do |task|
      if !task.claim_basis_current?
        "#{task.stage}：材料或申报已变化，需重新发起并签署"
      elsif task.status != "approved"
        "#{task.stage}：前置任务尚未全部通过"
      end
    end
  end
end
