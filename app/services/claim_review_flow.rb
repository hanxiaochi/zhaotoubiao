class ClaimReviewFlow
  class InvalidTransition < StandardError; end
  class StageForbidden < StandardError; end

  STAGES = %w[initial professional project_manager principal].freeze
  STAGE_LABELS = {
    "initial" => "经办初审",
    "professional" => "律师/专业复核",
    "project_manager" => "项目负责人复核",
    "principal" => "负责人终审"
  }.freeze

  def initialize(claim, user)
    @claim = claim
    @user = user
  end

  def allowed?
    return false unless @user.active? && ProjectPolicy.new(@user, @claim.project).show?
    return true if @user.admin?

    case @claim.review_stage
    when "initial"
      project_member? || @user.allowed?("claims.review")
    when "professional"
      project_role?("lawyer") || global_role?("professional")
    when "project_manager"
      @claim.project.owner_id == @user.id || project_role?("manager") || global_role?("project_manager")
    when "principal"
      global_role?("principal")
    else
      false
    end
  end

  def transition_for(stage:, decision:)
    raise InvalidTransition, "该债权已完成审核" if @claim.status.in?(%w[approved rejected])
    raise InvalidTransition, "请先完成补正并重新提交" if @claim.status == "supplement_required"
    raise InvalidTransition, "当前应处理层级为#{stage_label}" unless stage == @claim.review_stage
    raise StageForbidden, "当前用户无权处理#{stage_label}" unless allowed?

    case decision
    when "approve"
      material_issues = @claim.supplement_issues
      raise InvalidTransition, "材料核验未完成：#{material_issues.first(5).join('；')}。详见补正清单。" if material_issues.any?
      issues = ClaimWorkflowGate.issues(@claim)
      raise InvalidTransition, issues.join("；") if issues.any?
      advance
    when "request_supplement"
      { status: "supplement_required", review_stage: @claim.review_stage }
    when "reject"
      { status: "rejected", review_stage: @claim.review_stage }
    else
      raise InvalidTransition, "不支持的审核决定"
    end
  end

  def stage_label = STAGE_LABELS.fetch(@claim.review_stage, @claim.review_stage)

  private

  def advance
    index = STAGES.index(@claim.review_stage)
    raise InvalidTransition, "审核层级无效" unless index

    next_stage = STAGES[index + 1]
    next_stage ? { status: "pending_approval", review_stage: next_stage } : { status: "approved", review_stage: @claim.review_stage }
  end

  def project_member?
    @claim.project.owner_id == @user.id || @claim.project.project_memberships.where.not(membership_role: "observer").exists?(user_id: @user.id)
  end

  def project_role?(role)
    @claim.project.project_memberships.exists?(user_id: @user.id, membership_role: role)
  end

  def global_role?(code)
    @user.roles.exists?(code: code)
  end
end
