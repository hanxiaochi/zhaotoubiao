class ClaimChecklistsController < ApplicationController
  before_action :set_project
  before_action :set_checklist, only: %i[edit update]

  def new
    @checklist = @project.claim_checklists.new(active: true, claim_type: "unknown", material_types: ClaimChecklist::DEFAULT_MATERIAL_TYPES)
    authorize @checklist
  end

  def create
    @checklist = @project.claim_checklists.new(checklist_params.merge(created_by: current_user))
    authorize @checklist
    ClaimChecklist.transaction do
      @checklist.save!
      Audit::Recorder.call(action: "claim_checklist.create", record: @checklist)
    end
    redirect_to @project, notice: "债权材料清单模板已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @checklist
  end

  def update
    authorize @checklist
    @checklist.with_lock do
      authorize @checklist
      before_data = @checklist.attributes
      @checklist.update!(checklist_params)
      Audit::Recorder.call(action: "claim_checklist.update", record: @checklist, before_data: before_data)
    end
    redirect_to @project, notice: "债权材料清单模板已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_checklist
    @checklist = @project.claim_checklists.find_by!(public_id: params[:id])
  end

  def checklist_params
    permitted = params.require(:claim_checklist).permit(:name, :claim_type, :active, :material_types_text)
    permitted.except(:material_types_text).merge(material_types: permitted[:material_types_text].to_s.lines.map(&:strip).reject(&:blank?))
  end
end
