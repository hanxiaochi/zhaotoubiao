class Role < ApplicationRecord
  AVAILABLE_PERMISSIONS = {
    "projects.manage" => "管理全部项目",
    "claims.review" => "复核债权申报",
    "documents.approve" => "审批业务文稿",
    "bids.review" => "复核投标分析",
    "library.view" => "查阅企业资质与案例",
    "library.manage" => "维护企业资质与案例",
    "tenders.manage" => "管理招标模板与信息",
    "tenders.sources" => "管理招标数据源",
    "ai.review" => "审批 AI 建议",
    "audit.view" => "查看审计日志"
  }.freeze
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :code, :name, presence: true
  validates :code, uniqueness: true
  validate :permissions_are_strings

  private

  def permissions_are_strings
    errors.add(:permissions, "必须为权限字符串数组") unless permissions.is_a?(Array) && permissions.all?(String)
  end
end
