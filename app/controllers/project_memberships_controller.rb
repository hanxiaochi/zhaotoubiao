class ProjectMembershipsController < ApplicationController
  before_action :set_project
  before_action :set_membership, only: %i[update destroy]

  def create
    @membership = @project.project_memberships.new(membership_params)
    authorize @membership
    ProjectMembership.transaction do
      @membership.save!
      Notification.create!(user: @membership.user, kind: "project.assigned", title: "您已加入项目", body: @project.name, link: project_path(@project))
      Audit::Recorder.call(action: "project_membership.create", record: @membership)
    end
    redirect_to @project, notice: "项目成员已添加。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @project, alert: error.record.errors.full_messages.to_sentence
  end

  def update
    authorize @membership
    @membership.with_lock do
      authorize @membership
      before_data = @membership.attributes
      @membership.update!(membership_params.except(:user_id))
      Audit::Recorder.call(action: "project_membership.update", record: @membership, before_data: before_data)
    end
    redirect_to @project, notice: "项目成员角色已更新。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @project, alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    authorize @membership
    return redirect_to(@project, alert: "项目负责人不能从成员列表移除。") if @membership.user_id == @project.owner_id

    @membership.with_lock do
      authorize @membership
      before_data = @membership.attributes
      @membership.destroy!
      Audit::Recorder.call(action: "project_membership.remove", record: @membership, before_data: before_data, after_data: { removed: true })
    end
    redirect_to @project, notice: "项目成员已移除。"
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed
    redirect_to @project, alert: "移除成员未完成，原成员关系已保留，请稍后重试。"
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_membership
    @membership = @project.project_memberships.find(params[:id])
  end

  def membership_params
    params.require(:project_membership).permit(:user_id, :membership_role)
  end
end
