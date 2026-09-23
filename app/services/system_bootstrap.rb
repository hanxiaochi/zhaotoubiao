class SystemBootstrap
  class AlreadyInitialized < StandardError; end

  def self.call(attributes)
    User.transaction do
      # The unique admin-role row serializes competing first-use requests across workers.
      role = Role.find_or_create_by!(code: "admin") { |item| item.name = "系统管理员"; item.permissions = [ "*" ] }
      role.with_lock do
        raise AlreadyInitialized if User.exists?
        user = User.create!(attributes.merge(status: "active"))
        user.roles << role
        { "bankruptcy" => "破产管理部", "tender" => "招标代理部", "audit" => "审计与评估部" }.each do |code, name|
          Department.find_or_create_by!(code: code) { |department| department.name = name }
        end
        {
          "project_manager" => [ "项目经理", %w[projects.manage claims.review documents.approve bids.review ai.review] ],
          "professional" => [ "专业人员", %w[claims.review bids.review] ],
          "member" => [ "项目成员", [] ]
        }.each do |code, (name, permissions)|
          Role.find_or_create_by!(code: code) { |item| item.name = name; item.permissions = permissions }
        end
        Current.set(user: user) { Audit::Recorder.call(action: "system.bootstrap", record: user) }
        user
      end
    end
  end
end
