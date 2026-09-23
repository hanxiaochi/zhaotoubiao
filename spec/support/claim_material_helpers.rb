module ClaimMaterialHelpers
  # Synthetic evidence only: successful workflow fixtures must meet the same gate as real claims.
  def verify_claim_materials(claim)
    claim.reload
    document = claim.project.project_documents.create!(
      uploaded_by: claim.created_by, category: "claim", status: "uploaded",
      original_filename: "synthetic-review.txt", ocr_status: "not_required",
      file: { io: StringIO.new("Synthetic claim evidence for automated tests"), filename: "synthetic-review.txt", content_type: "text/plain" }
    )
    claim.claim_materials.create!(material_type: "合成申报书") unless claim.claim_materials.exists?
    claim.claim_materials.each do |material|
      material.update!(project_document: document, present: true, checked_by: claim.created_by,
        material_requirement: "required", signature_requirement: "required", seal_requirement: "required",
        authorization_requirement: "required", signature_detected: true, seal_detected: true, authorization_complete: true)
    end
    claim.reload
  end
end
