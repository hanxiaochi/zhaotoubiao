class TenderTemplatesController < ApplicationController
  before_action :set_template, only: %i[show edit update]

  def index
    authorize TenderTemplate
    templates = policy_scope(TenderTemplate)
    templates = templates.where(project_category: params[:category]) if params[:category].present?
    templates = templates.where(tender_method: params[:method]) if params[:method].present?
    if params[:q].present?
      templates = templates.where("name LIKE ?", "%#{TenderTemplate.sanitize_sql_like(params[:q].to_s)}%")
    end
    @total = templates.count
    @page = [ params[:page].to_i, 1 ].max
    @templates = templates.order(active: :desc, updated_at: :desc, id: :desc).limit(30).offset((@page - 1) * 30)
  end

  def show
    authorize @template
    projects = policy_scope(Project).where(project_type: %w[tender_agency bid])
    projects = projects.where(owner: current_user) unless current_user.admin? || current_user.allowed?("projects.manage")
    if params[:q].present?
      query = "%#{Project.sanitize_sql_like(params[:q].to_s)}%"
      projects = projects.where("name LIKE :query OR code LIKE :query", query: query)
    end
    @total = projects.count
    @page = [ params[:page].to_i, 1 ].max
    @projects = projects.order(updated_at: :desc, id: :desc).limit(30).offset((@page - 1) * 30)
  end

  def new
    @template = TenderTemplate.new(active: true, revision_number: 1)
    authorize @template
  end

  def create
    @template = TenderTemplate.new(template_params.merge(created_by: current_user, revision_number: 1))
    authorize @template
    TenderTemplate.transaction do
      @template.save!
      Audit::Recorder.call(action: "tender_template.create", record: @template)
    end
    redirect_to @template, notice: "招标模板已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @template
  end

  def update
    authorize @template
    @template.with_lock do
      before_data = @template.attributes
      @template.update!(template_params.merge(revision_number: @template.revision_number + 1))
      Audit::Recorder.call(action: "tender_template.update", record: @template, before_data: before_data)
    end
    redirect_to @template, notice: "模板已更新并形成新版本。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_template
    @template = TenderTemplate.find_by!(public_id: params[:id])
  end

  def template_params
    params.require(:tender_template).permit(:name, :project_category, :tender_method, :body, :active)
  end
end
