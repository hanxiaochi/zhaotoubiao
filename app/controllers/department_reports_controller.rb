class DepartmentReportsController < ApplicationController
  def index
    authorize Project, :index?
    visible = policy_scope(Project)
    @departments = Department.where(id: Project.where(id: visible.select(:id)).select(:department_id)).order(:name)
    projects = visible
    if params[:view] == "completed_tenders"
      projects = projects.where(project_type: %w[tender_agency bid], status: %w[completed archived])
    end
    if params[:department_id].present?
      department_id = params[:department_id] == "unassigned" ? nil : params[:department_id]
      projects = projects.where(department_id: department_id)
    end
    projects = projects.where(project_type: params[:type]) if params[:type].present?
    projects = projects.where(status: params[:status]) if params[:status].present?
    from = Date.iso8601(params[:from]) if params[:from].present?
    to = Date.iso8601(params[:to]) if params[:to].present?
    raise Date::Error if from && to && from > to
    projects = projects.where(start_date: from..) if from
    projects = projects.where(start_date: ..to) if to
    @report = DepartmentReport.new(projects)
    @page = [ params[:page].to_i, 1 ].max
    @projects = @report.projects.includes(:department, :owner).order(updated_at: :desc, id: :desc).limit(30).offset((@page - 1) * 30)
    respond_to do |format|
      format.html
      format.csv do
        Audit::Recorder.call(action: "department_report.export", record: current_user, after_data: { filters: filter_params.to_h, visible_projects: @report.totals[:projects] })
        response.headers["Cache-Control"] = "private, no-store"
        send_data @report.to_csv, filename: "department-report-#{Date.current}.csv", type: "text/csv; charset=utf-8", disposition: "attachment"
      end
    end
  rescue Date::Error
    redirect_to department_reports_path, alert: "项目开始日期区间无效，请使用正确日期且起始不晚于截止。"
  end

  private

  def filter_params
    params.permit(:department_id, :type, :status, :from, :to, :view)
  end
end
