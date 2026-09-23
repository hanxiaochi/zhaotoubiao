class ProjectMilestonesController < ApplicationController
  before_action :set_project
  before_action :set_milestone, only: %i[edit update]

  def new
    @milestone = @project.project_milestones.new(status: "pending")
    authorize @milestone
    prepare_form
  end

  def create
    @milestone = @project.project_milestones.new(milestone_params)
    authorize @milestone
    apply_completion_date
    ProjectMilestone.transaction do
      @milestone.save!
      Audit::Recorder.call(action: "project_milestone.create", record: @milestone)
      notify_owner("收到新的项目里程碑")
    end
    redirect_to @project, notice: "项目里程碑已创建。"
  rescue ActiveRecord::RecordInvalid
    prepare_form
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @milestone
    prepare_form
  end

  def update
    authorize @milestone
    @milestone.with_lock do
      authorize @milestone
      before_data = @milestone.attributes
      @milestone.assign_attributes(milestone_params)
      apply_completion_date
      @milestone.save!
      Audit::Recorder.call(action: "project_milestone.update", record: @milestone, before_data: before_data)
    end
    redirect_to @project, notice: "项目里程碑已更新。"
  rescue ActiveRecord::RecordInvalid
    prepare_form
    render :edit, status: :unprocessable_content
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_milestone
    @milestone = @project.project_milestones.find_by!(public_id: params[:id])
  end

  def milestone_params
    params.require(:project_milestone).permit(:title, :stage, :status, :due_on, :owner_id, :note)
  end

  def prepare_form
    @owners = User.active.where(id: @project.members.select(:id)).or(User.active.where(id: @project.owner_id)).distinct.order(:name)
  end

  def apply_completion_date
    @milestone.completed_on = @milestone.status == "completed" ? (@milestone.completed_on || Date.current) : nil
  end

  def notify_owner(title)
    return unless @milestone.owner && @milestone.owner != current_user

    @milestone.owner.notifications.create!(kind: "project.milestone", title: title, body: "#{@project.name} · #{@milestone.title}", link: project_path(@project))
  end
end
