class WorkflowTasksController < ApplicationController
  before_action :set_project, only: %i[new create]
  before_action :set_task, only: %i[show decide restart]

  def index
    authorize WorkflowTask
    @tasks = policy_scope(WorkflowTask).includes(:project, :assignee).order(Arel.sql("CASE WHEN due_at IS NULL THEN 1 ELSE 0 END"), :due_at, created_at: :desc)
    @tasks = @tasks.where(status: params[:status]) if params[:status].present?
  end

  def new
    @task = @project.workflow_tasks.new(status: "pending", record: params[:record_ref].present? ? resolve_record(params[:record_ref]) : @project)
    authorize @task
    prefill_bid_suggestion if params[:suggested_task_index].present?
    prepare_form
  end

  def create
    @task = @project.workflow_tasks.new(task_params.except(:record_ref, :signer_ids).merge(status: "pending"))
    @task.record = resolve_record(task_params[:record_ref])
    authorize @task
    Array(task_params[:signer_ids]).reject(&:blank?).uniq.each { |id| @task.workflow_signatures.build(user_id: id) }
    @task.record.with_lock do
      authorize @task
      @task.save!
      notify_assignees(@task)
      Audit::Recorder.call(action: "workflow_task.create", record: @task)
    end
    redirect_to @task, notice: "审批任务已创建并通知处理人。"
  rescue ActiveRecord::RecordInvalid
    prepare_form
    render :new, status: :unprocessable_content
  end

  def show
    authorize @task
    @events = @task.workflow_events.includes(:actor).order(created_at: :desc)
  end

  def decide
    authorize @task, :decide?
    decision = params.require(:decision)
    comment = params.require(:comment)
    @task.record.with_lock do
      @task.with_lock do
        authorize @task, :decide?
        @task.workflow_events.create!(actor: current_user, decision: decision, comment: comment)
        next_status = @task.countersign? ? countersign_status(decision, comment) : status_for(decision)
        @task.update!(status: next_status, completed_at: next_status.in?(%w[approved rejected returned]) ? Time.current : nil)
        Notification.create!(user: @task.project.owner, kind: "workflow.decided", title: "审批任务有新处理意见", body: "#{@task.stage} · #{decision}", link: workflow_task_path(@task)) if @task.project.owner && @task.project.owner != current_user
        ClaimReviewNotifier.call(@task.record) if @task.claim_gate? && next_status == "approved" && ClaimWorkflowGate.issues(@task.record).empty?
        Audit::Recorder.call(action: "workflow_task.decide", record: @task, after_data: { decision: decision, comment: comment })
      end
    end
    redirect_to @task, notice: "处理意见已记录。"
  rescue KeyError, ActiveRecord::RecordInvalid, ActionController::ParameterMissing => error
    redirect_to @task, alert: error.message.to_s.first(160)
  end

  def restart
    authorize @task, :restart?
    replacement = nil
    @task.record.with_lock do
      @task.with_lock do
        authorize @task, :restart?
        replacement = @task.project.workflow_tasks.new(record: @task.record, stage: @task.stage,
          assignee: @task.assignee, due_at: params[:due_at].presence || @task.due_at,
          replaces_task: @task, restart_reason: params.require(:restart_reason))
        @task.workflow_signatures.order(:id).each { |signature| replacement.workflow_signatures.build(user: signature.user) }
        replacement.save!
        notify_assignees(replacement)
        Audit::Recorder.call(action: "workflow_task.restart", record: replacement,
          after_data: { previous_task: @task.public_id, reason: replacement.restart_reason, claim_review_stage: replacement.claim_review_stage })
      end
    end
    redirect_to replacement, notice: "已保留原任务并发起新一轮；全部原办理人需重新签署。"
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing => error
    redirect_to @task, alert: "不能重新发起：#{error.message.to_s.first(160)}"
  end

  private

  def prefill_bid_suggestion
    index = params[:suggested_task_index].to_s
    raise ActiveRecord::RecordNotFound unless @task.record.is_a?(BidAnalysis) && index.match?(/\A\d{1,4}\z/)
    suggestion = @task.record.suggested_tasks[index.to_i]
    raise ActiveRecord::RecordNotFound unless suggestion.present?
    @task.stage = suggestion
  end

  def notify_assignees(task)
    task.pending_recipients.each do |user|
      Notification.create!(user: user, kind: "workflow.assigned", title: task.countersign? ? "收到新的会签任务" : "收到新的审批任务",
        body: "#{task.project.name} · #{task.stage}", link: workflow_task_path(task))
    end
  end

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_task
    @task = WorkflowTask.find_by!(public_id: params[:id])
  end

  def task_params
    params.require(:workflow_task).permit(:stage, :assignee_id, :due_at, :record_ref, signer_ids: [])
  end

  def prepare_form
    @assignees = User.active.where(id: @project.members.select(:id)).or(User.active.where(id: @project.owner_id)).distinct.order(:name)
    @record_options = [ [ "项目：#{@project.name}", "Project:#{@project.public_id}" ] ]
    @record_options += @project.claims.order(:creditor_name).map { |item| [ "债权：#{item.creditor_name}", "Claim:#{item.public_id}" ] }
    @record_options += @project.project_documents.where.not(status: "archived").map { |item| [ "文件：#{item.original_filename}", "ProjectDocument:#{item.public_id}" ] }
    @record_options += @project.bid_analyses.map { |item| [ "投标分析：#{item.public_id.first(8)}", "BidAnalysis:#{item.public_id}" ] }
    @record_options += @project.generated_documents.map { |item| [ "文稿：#{item.title}", "GeneratedDocument:#{item.public_id}" ] }
  end

  def resolve_record(reference)
    type, public_id = reference.to_s.split(":", 2)
    klass = { "Project" => Project, "Claim" => Claim, "ProjectDocument" => ProjectDocument, "BidAnalysis" => BidAnalysis, "GeneratedDocument" => GeneratedDocument }[type]
    raise ActiveRecord::RecordNotFound unless klass
    record = klass.find_by!(public_id: public_id)
    record_project_id = record.is_a?(Project) ? record.id : record.project_id
    raise ActiveRecord::RecordNotFound unless record_project_id == @project.id

    record
  end

  def status_for(decision)
    { "approve" => "approved", "reject" => "rejected", "return" => "returned", "complete" => "approved", "comment" => "active" }.fetch(decision)
  end

  def countersign_status(decision, comment)
    return "active" if decision == "comment"

    signature = @task.workflow_signatures.find_by!(user_id: current_user.id, status: "pending")
    signature.update!(status: status_for(decision), comment: comment, decided_at: Time.current)
    return "rejected" if decision == "reject"
    return "returned" if decision == "return"

    @task.workflow_signatures.where.not(status: "approved").exists? ? "active" : "approved"
  end
end
