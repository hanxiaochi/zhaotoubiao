class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update ledger]

  LEDGERS = {
    "claims" => [ "债权台账", :claims, :creditor_name ],
    "assets" => [ "资产台账", :assets, :name ],
    "documents" => [ "文件档案", :project_documents, :original_filename ],
    "intake" => [ "接管资料", :intake_items, :name ],
    "drafts" => [ "业务文稿", :generated_documents, :title ],
    "bids" => [ "投标分析台账", :bid_analyses, :public_id ]
  }.freeze

  def ledger
    authorize @project, :show?
    @ledger_kind = params[:kind].presence || "claims"
    definition = LEDGERS[@ledger_kind]
    raise ActiveRecord::RecordNotFound unless definition

    @ledger_title, association, @name_field = definition
    records = @project.public_send(association)
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
      records = if @ledger_kind == "bids"
        records.where("public_id LIKE :q OR CAST(criteria AS TEXT) LIKE :q", q: query)
      elsif @ledger_kind == "assets"
        records.where("name LIKE :q OR asset_code LIKE :q OR rights_no LIKE :q OR address LIKE :q OR source_reference LIKE :q OR description LIKE :q", q: query)
      else
        records.where("#{records.klass.connection.quote_column_name(@name_field)} LIKE ?", query)
      end
    end
    @total = records.count
    @page = [ params[:page].to_i, 1 ].max
    @records = records.order(created_at: :desc, id: :desc).limit(30).offset((@page - 1) * 30)
  end

  def index
    authorize Project
    visible_projects = policy_scope(Project)
    @departments = Department.where(id: visible_projects.select(:department_id)).order(:name)
    @owners = User.where(id: visible_projects.select(:owner_id)).order(:name)
    @projects = visible_projects.includes(:department, :owner).order(updated_at: :desc, id: :desc)
    @projects = @projects.where(project_type: params[:type]) if params[:type].present?
    @projects = @projects.where(status: params[:status]) if params[:status].present?
    @projects = @projects.where(department_id: params[:department_id]) if params[:department_id].present?
    @projects = @projects.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    due_from = Date.iso8601(params[:due_from]) if params[:due_from].present?
    due_to = Date.iso8601(params[:due_to]) if params[:due_to].present?
    if due_from && due_to && due_from > due_to
      redirect_to projects_path, alert: "截止日期起不能晚于截止日期止。"
      return
    end
    @projects = @projects.where(due_date: due_from..) if due_from
    @projects = @projects.where(due_date: ..due_to) if due_to
    @projects = @projects.where("projects.name LIKE :q OR projects.code LIKE :q", q: "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @total = @projects.count
    @page = params[:page].to_i.clamp(1, [ (@total / 30.0).ceil, 1 ].max)
    @projects = @projects.limit(30).offset((@page - 1) * 30)
  rescue Date::Error
    redirect_to projects_path, alert: "截止日期筛选格式不正确。"
  end

  def show
    authorize @project
    @assets = @project.assets.order(updated_at: :desc).limit(10)
    @claims = @project.claims.order(updated_at: :desc).limit(10)
    @intake_items = @project.intake_items.order(updated_at: :desc).limit(10)
    @documents = @project.project_documents.where.not(status: "archived").order(updated_at: :desc).limit(10)
    @fees = @project.fees.order(created_at: :desc).limit(10)
    @fee_summary = @project.fees.group(:fee_type).sum(:receivable).map do |kind, receivable|
      records = @project.fees.where(fee_type: kind)
      { kind: kind, receivable: receivable, received: records.sum(:received),
        outstanding: records.sum("CASE WHEN receivable > received THEN receivable - received ELSE 0 END"),
        overpaid: records.sum("CASE WHEN received > receivable THEN received - receivable ELSE 0 END") }
    end
    @bid_analyses = @project.bid_analyses.order(updated_at: :desc).limit(5)
    @generated_documents = @project.generated_documents.order(updated_at: :desc).limit(8)
    @memberships = @project.project_memberships.includes(:user).order(:membership_role, :created_at)
    @milestones = @project.project_milestones.includes(:owner).order(Arel.sql("CASE WHEN due_on IS NULL THEN 1 ELSE 0 END"), :due_on, :created_at)
    @claim_checklists = @project.claim_checklists.order(active: :desc, claim_type: :asc, name: :asc)
  end

  def new
    @project = Project.new(owner: current_user, start_date: Date.current)
    authorize @project
  end

  def create
    @project = Project.new(project_params.merge(owner: current_user))
    authorize @project
    apply_archive_metadata
    Project.transaction do
      @project.save!
      @project.project_memberships.create!(user: current_user, membership_role: "owner")
      Audit::Recorder.call(action: "project.create", record: @project)
    end
    redirect_to @project, notice: "项目已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @project
  end

  def update
    authorize @project
    @project.with_lock do
      authorize @project
      before_data = @project.attributes
      @project.assign_attributes(project_params)
      apply_archive_metadata
      @project.save!
      Audit::Recorder.call(action: "project.update", record: @project, before_data: before_data)
    end
    redirect_to @project, notice: "项目已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:id])
  end

  def project_params
    params.require(:project).permit(:code, :name, :project_type, :status, :department_id, :start_date, :due_date, :description, :client_name, :project_category, :tender_method, :budget_amount, :archive_reason)
  end

  def apply_archive_metadata
    if @project.status == "archived"
      @project.archived_at ||= Time.current
      @project.archived_by ||= current_user
    elsif @project.status_changed?
      @project.archived_at = nil
      @project.archived_by = nil
      @project.archive_reason = nil
    end
  end
end
