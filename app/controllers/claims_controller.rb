class ClaimsController < ApplicationController
  before_action :set_project, only: %i[new create]
  before_action :set_claim, only: %i[show edit update review resubmit]

  def resubmit
    authorize @claim, :resubmit?
    @claim.with_lock do
      authorize @claim, :resubmit?
      @claim.claim_supplements.create!(
        submitted_by: current_user,
        note: params[:note],
        review_stage: @claim.review_stage,
        material_snapshot: @claim.claim_materials.order(:id).map { |material| material.attributes.except("created_at", "updated_at") }
      )
      @claim.update!(status: "pending_approval")
      ClaimReviewNotifier.call(@claim)
      Audit::Recorder.call(action: "claim.resubmit", record: @claim, after_data: { stage: @claim.review_stage, remaining_issues: @claim.supplement_issues })
    end
    redirect_to @claim, notice: "补正说明已提交，回到原审核层级等待复核。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @claim, alert: error.record.errors.full_messages.to_sentence
  end

  def show
    authorize @claim
    @materials = @claim.claim_materials.order(:material_type)
    @reviews = @claim.claim_reviews.includes(:reviewer).order(created_at: :desc)
    @project_documents = @claim.project.project_documents.where.not(status: "archived").order(:original_filename)
    @ai_runs = @claim.project.ai_runs.where(record: @claim).order(created_at: :desc)
    @review_flow = ClaimReviewFlow.new(@claim, current_user)
    @supplements = @claim.claim_supplements.includes(:submitted_by).order(created_at: :desc)
    @claim_tasks = ClaimWorkflowGate.tasks(@claim)
    @gate_issues = ClaimWorkflowGate.issues(@claim)
  end

  def new
    @claim = @project.claims.new(currency: "CNY", claimed_type: "unknown")
    authorize @claim
    prepare_checklists
    prepare_source_document
  end

  def create
    @claim = @project.claims.new(claim_params.merge(created_by: current_user))
    authorize @claim
    checklist = selected_checklist
    unless checklist.nil? || checklist.applicable_to?(@claim.claimed_type)
      @claim.errors.add(:claimed_type, "与所选材料清单模板不匹配")
      raise ActiveRecord::RecordInvalid, @claim
    end
    Claim.transaction do
      @claim.save!
      material_types_for(checklist).each { |material_type| @claim.claim_materials.create!(material_type: material_type) }
      attach_source_document
      Audit::Recorder.call(action: "claim.create", record: @claim, after_data: { checklist_id: checklist&.public_id })
    end
    redirect_to @claim, notice: "债权申报已登记，并生成适用的材料清单。"
  rescue ActiveRecord::RecordInvalid
    prepare_checklists
    prepare_source_document
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @claim
  end

  def update
    authorize @claim
    @claim.with_lock do
      authorize @claim
      before_data = @claim.attributes
      @claim.assign_attributes(claim_params)
      changed = @claim.changed?
      @claim.save!
      ClaimReviewRevision.after_change!(@claim) if changed
      Audit::Recorder.call(action: "claim.update", record: @claim, before_data: before_data)
    end
    redirect_to @claim, notice: "债权申报已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  def review
    authorize @claim, :review?
    @claim.with_lock do
      authorize @claim, :review?
      flow = ClaimReviewFlow.new(@claim, current_user)
      transition = flow.transition_for(stage: params.require(:stage), decision: params.require(:decision))
      @claim.claim_reviews.create!(reviewer: current_user, stage: params[:stage], decision: params[:decision], comment: params[:comment],
        basis_sha256: ClaimWorkflowGate.basis(@claim), evidence_snapshot: ClaimReviewRevision.snapshot(@claim))
      @claim.update!(transition)
      ClaimReviewNotifier.call(@claim)
      Audit::Recorder.call(action: "claim.review", record: @claim, after_data: { decision: params[:decision], stage: params[:stage] })
    end
    redirect_to @claim, notice: "审核意见已记录并同步台账状态。"
  rescue ActiveRecord::RecordInvalid, ClaimReviewFlow::InvalidTransition, ClaimReviewFlow::StageForbidden => error
    message = error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message
    redirect_to @claim, alert: message
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_claim
    @claim = Claim.find_by!(public_id: params[:id])
  end

  def claim_params
    params.require(:claim).permit(:creditor_name, :unified_code, :contact_name, :contact_phone, :claim_amount, :currency, :claimed_type, :summary)
  end

  def default_materials
    ClaimChecklist::DEFAULT_MATERIAL_TYPES
  end

  def prepare_checklists
    @claim_checklists = @project.claim_checklists.where(active: true).order(:claim_type, :name)
  end

  def selected_checklist
    return if params[:claim_checklist_id].blank?

    @project.claim_checklists.where(active: true).find_by!(public_id: params[:claim_checklist_id])
  end

  def material_types_for(checklist)
    checklist&.material_types.presence || default_materials
  end

  def prepare_source_document
    @source_document = @project.project_documents.find_by(public_id: params[:source_document_id])
    return unless @source_document

    fields = @source_document.extracted_fields
    @claim.assign_attributes(
      creditor_name: fields["creditor_name"],
      unified_code: fields["unified_code"],
      contact_phone: fields["contact_phone"],
      claim_amount: fields["claim_amount"]
    )
  end

  def attach_source_document
    source = @project.project_documents.find_by(public_id: params[:source_document_id])
    return unless source && @claim.claim_materials.exists?(material_type: source.classification)

    material = @claim.claim_materials.find_by!(material_type: source.classification)
    indicators = source.metadata.fetch("review_indicators", {})
    locations = %w[signature seal authorization].filter_map { |key| indicators[key] if indicators.dig(key, "page").present? }
    locations << source.metadata.dig("field_sources", "creditor_name") if locations.empty?
    material.update!(
      project_document: source,
      present: source.classification_confidence.to_f >= 70,
      page_reference: locations.compact.map { |location| Ocr::SourceLabel.call(location) }.uniq.join("、"),
      extraction_confidence: source.classification_confidence,
      signature_detected: nil,
      seal_detected: nil,
      authorization_complete: nil,
      note: "系统仅依据 OCR 文本线索标记疑似签字、印章或授权页，须由经办人员查看原件并人工复核。"
    )
  end
end
