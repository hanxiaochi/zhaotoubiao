class ClaimMaterialsController < ApplicationController
  before_action :set_claim
  before_action :set_material

  def update
    authorize @claim, :update?
    @claim.with_lock do
      authorize @claim, :update?
      before_data = @material.attributes
      @material.update!(material_params.merge(checked_by: current_user))
      ClaimReviewRevision.after_change!(@claim) if @material.saved_changes.except("updated_at").any?
      Audit::Recorder.call(action: "claim.material.update", record: @material, before_data: before_data)
    end
    redirect_to @claim, notice: "材料核验状态已更新。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @claim, alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_claim
    @claim = Claim.find_by!(public_id: params[:claim_id])
  end

  def set_material
    @material = @claim.claim_materials.find(params[:id])
  end

  def material_params
    params.require(:claim_material).permit(:present, :signature_detected, :seal_detected, :authorization_complete, :page_reference, :note, :project_document_id, :extraction_confidence,
      :material_requirement, :signature_requirement, :seal_requirement, :authorization_requirement, :requirement_note)
  end
end
