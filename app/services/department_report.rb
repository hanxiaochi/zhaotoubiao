require "csv"

class DepartmentReport
  attr_reader :rows, :types, :statuses, :projects
  METRICS = %i[projects ongoing completed archived overdue claims pending_claims receivable received outstanding overpaid].freeze
  MONEY_METRICS = %i[receivable received outstanding overpaid].freeze

  def initialize(scope)
    @projects = Project.where(id: scope.select(:id))
    @statuses = projects.group(:status).count
    @types = projects.group(:project_type).count
    counts = projects.group(:department_id).count
    state_counts = projects.group(:department_id, :status).count
    names = Department.where(id: counts.keys.compact).pluck(:id, :name).to_h
    overdue = projects.where(status: %w[draft active reviewing]).where("due_date < ?", Date.current).group(:department_id).count
    claims = Claim.joins(:project).where(project_id: projects.select(:id))
    claim_counts = claims.group("projects.department_id").count
    pending = claims.where.not(status: %w[approved rejected]).group("projects.department_id").count
    fees = Fee.joins(:project).where(project_id: projects.select(:id)).group("projects.department_id")
    receivable = fees.sum(:receivable)
    received = fees.sum(:received)
    outstanding = fees.sum(Arel.sql("CASE WHEN receivable > received THEN receivable - received ELSE 0 END"))
    overpaid = fees.sum(Arel.sql("CASE WHEN received > receivable THEN received - receivable ELSE 0 END"))
    @rows = counts.map do |id, count|
      {
        department_id: id, name: names[id] || "未分配部门", projects: count,
        ongoing: %w[draft active reviewing].sum { |state| state_counts.fetch([ id, state ], 0) },
        completed: state_counts.fetch([ id, "completed" ], 0), archived: state_counts.fetch([ id, "archived" ], 0),
        overdue: overdue.fetch(id, 0), claims: claim_counts.fetch(id, 0), pending_claims: pending.fetch(id, 0),
        receivable: receivable.fetch(id, 0), received: received.fetch(id, 0),
        outstanding: outstanding.fetch(id, 0), overpaid: overpaid.fetch(id, 0)
      }
    end.sort_by { |row| [ row[:department_id].nil? ? 1 : 0, row[:name] ] }
  end

  def totals
    METRICS.to_h { |key| [ key, rows.sum { |row| row.fetch(key) } ] }
  end

  def to_csv
    "\uFEFF" + CSV.generate do |csv|
      csv << [ "部门", "项目数", "在办含草稿", "已完成", "已归档", "超期在办", "债权数", "待审债权", "应收CNY", "实收CNY", "未收CNY", "溢收CNY" ]
      rows.each do |row|
        csv << [ csv_text(row[:name]), *METRICS.map { |key| MONEY_METRICS.include?(key) ? format("%.2f", row.fetch(key)) : row.fetch(key) } ]
      end
    end
  end

  private

  def csv_text(value)
    value.match?(/\A\s*[=+@\-\t\r\n]/) ? "'#{value}" : value
  end
end
