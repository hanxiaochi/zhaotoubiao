class BidSimulation < ApplicationRecord
  include HasPublicId
  belongs_to :bid_analysis
  belongs_to :created_by, class_name: "User"
  belongs_to :source, polymorphic: true
  has_many :ai_runs, as: :record, dependent: :restrict_with_error
  validates :title, :source_text, :source_title, :basis_sha256, presence: true
  validates :confirmed_complete, acceptance: { accept: true }
  validates :status, inclusion: { in: %w[draft reviewed] }
  validates :total_score, numericality: { in: 0..100 }, allow_nil: true
  validate :valid_basis

  def project = bid_analysis.project

  def current_text
    case source
    when GeneratedDocument then source.content
    when ProjectDocument then source.ocr_text
    end
  end

  def current_rubric
    bid_analysis.bid_scores.where(active: true, criterion: bid_analysis.criteria).order(:id).map do |score|
      { "criterion_id" => score.public_id, "criterion" => score.criterion, "maximum" => score.maximum.to_s("F"), "rule" => score.scoring_rule.to_s }
    end
  end

  def basis_fingerprint
    source.reload
    bid_analysis.reload
    Digest::SHA256.hexdigest({ source: source.attributes, criteria: bid_analysis.criteria, rubric: current_rubric }.to_json)
  end

  def current_basis?
    source.present? && basis_sha256.present? && basis_sha256 == basis_fingerprint
  end

  def capture_basis
    self.source_text = current_text
    self.source_title = source.is_a?(GeneratedDocument) ? source.title : source.original_filename
    self.rubric = current_rubric
    self.basis_sha256 = basis_fingerprint
  end

  private

  def valid_basis
    unless source.is_a?(GeneratedDocument) || source.is_a?(ProjectDocument)
      errors.add(:source, "仅支持业务文稿或已解析项目文件")
      return
    end
    errors.add(:source, "必须属于当前项目") unless source.project_id == bid_analysis&.project_id
    errors.add(:source, "归档文件不能作为新模拟审核来源") if new_record? && source.status == "archived"
    if new_record? && source.is_a?(ProjectDocument) && source.ocr_status != "completed"
      errors.add(:source, "项目文件需先完成全文解析/OCR并人工核对完整性")
    end
    errors.add(:source_text, "全文超过 100000 字符，当前模型单次审核范围不足；未截断或提交") if source_text.to_s.length > 100_000
    unless rubric.is_a?(Array) && rubric.all? { |row| row.is_a?(Hash) && %w[criterion_id criterion maximum rule].all? { |field| row[field].is_a?(String) } }
      errors.add(:rubric, "必须是包含评分点标识、名称、满分和规则的量表数组")
      return
    end
    if rubric.blank? || rubric.any? { |row| row["rule"].blank? }
      errors.add(:rubric, "每个评分点必须填写评分标准原文")
    end
    if rubric.map { |row| row["criterion"] }.sort != Array(bid_analysis&.criteria).uniq.sort
      errors.add(:rubric, "评分条目必须覆盖当前全部评分点")
    end
    maxima = rubric.map { |row| BigDecimal(row.fetch("maximum"), exception: false) }
    unless maxima.all? { |maximum| maximum&.finite? && maximum > 0 && maximum <= 100 }
      errors.add(:rubric, "每项满分必须是大于 0 且不超过 100 的有限数字")
      return
    end
    ids = rubric.pluck("criterion_id")
    errors.add(:rubric, "评分点标识不能为空或重复") if ids.any?(&:blank?) || ids.uniq.size != ids.size
    total = maxima.sum(BigDecimal("0"))
    errors.add(:rubric, "满分合计必须为 100") unless total == 100
  end
end
