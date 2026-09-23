class BidScoringReport
  attr_reader :analysis, :rows, :issues

  def initialize(analysis)
    @analysis = analysis
    @rows = analysis.bid_scores.includes(:project_document, :updated_by).order(:id).to_a
    @issues = []
    if rows.any?
      issues << "缺少当前评分点" if analysis.criteria.empty?
      missing = analysis.criteria.uniq - current_rows.map(&:criterion)
      missing.each { |criterion| issues << "#{criterion}：尚未填写分值" }
      rows.select { |row| row.active? && !analysis.criteria.include?(row.criterion) }.each do |row|
        issues << "#{row.criterion}：评分点已变更，请停用旧记录并重新评分"
      end
      current_rows.each { |row| row.evidence_issues.each { |issue| issues << "#{row.criterion}：#{issue}" } }
      issues << "评分满分合计为 #{maximum.to_s('F')}，尚未覆盖完整 100 分" unless maximum == 100
    end
  end

  def current_rows = rows.select { |row| row.active? && analysis.criteria.include?(row.criterion) }
  def maximum = current_rows.sum(BigDecimal("0"), &:maximum)
  def awarded = current_rows.sum(BigDecimal("0"), &:awarded)
  def ready? = rows.any? && issues.empty?
end
