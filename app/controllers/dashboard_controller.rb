class DashboardController < ApplicationController
  def index
    projects = policy_scope(Project)
    personal_tasks = WorkflowTask.pending_for(current_user, projects: projects)
    @stats = {
      projects: projects.where(status: %w[draft active reviewing]).count,
      active_claims: Claim.where(project_id: projects.select(:id)).where.not(status: %w[approved rejected]).count,
      pending_tasks: personal_tasks.count,
      receivable: Fee.where(project_id: projects.select(:id)).sum(:receivable),
      received: Fee.where(project_id: projects.select(:id)).sum(:received)
    }
    @recent_projects = projects.includes(:department, :owner).order(updated_at: :desc).limit(8)
    @my_tasks = personal_tasks.includes(:project).order(Arel.sql("CASE WHEN due_at IS NULL THEN 1 ELSE 0 END"), :due_at).limit(8)
  end
end
