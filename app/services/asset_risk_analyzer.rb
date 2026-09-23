class AssetRiskAnalyzer
  def self.call(asset) = new(asset).call

  def initialize(asset)
    @asset = asset
  end

  def call
    flags = []
    flags << flag("missing_rights_no", "未登记权证编号，唯一性核验依据不足") if @asset.rights_no.blank?
    flags << flag("missing_appraisal", "评估机构或评估价值尚未完整登记") if @asset.appraisal_org.blank? || @asset.appraisal_value.nil?
    flags.concat(duplicate_flags)
    flags.concat(similar_flags)
    flags
  end

  private

  def duplicate_flags
    candidates = @asset.project.assets.where.not(id: @asset.id)
    matches = []
    if @asset.rights_no.present?
      related = candidates.where("LOWER(TRIM(rights_no)) = ?", normalize(@asset.rights_no)).pluck(:public_id)
      matches << flag("duplicate_rights_no", "发现相同权证编号的资产记录", related) if related.any?
    end
    if @asset.address.present?
      related = candidates.where("LOWER(REPLACE(TRIM(address), ' ', '')) = ?", normalize(@asset.address).delete(" ")).pluck(:public_id)
      matches << flag("duplicate_address", "发现相同地址的资产记录，需核对是否重复评估", related) if related.any?
    end
    matches
  end

  def normalize(value) = value.to_s.strip.downcase

  def similar_flags
    target = similarity_fields(@asset)
    return [] if target.values.all?(&:empty?)

    # Stream same-project records in batches; do not silently ignore older assets.
    matches = []
    match_count = 0
    @asset.project.assets.where.not(id: @asset.id).select(:id, :public_id, :name, :category, :address, :source_reference, :description).find_each do |candidate|
      fields = similarity_fields(candidate)
      reasons = []
      reasons << "相同合同/来源编号" if target[:source].present? && target[:source] == fields[:source]
      if normalized_text(@asset.category) == normalized_text(candidate.category)
        { name: "名称", address: "地址", description: "来源说明" }.each do |field, label|
          score = dice(target[field], fields[field])
          reasons << "#{label}文字相似#{(score * 100).round}%" if score >= 0.8
        end
      end
      next if reasons.empty?
      match_count += 1
      matches << flag("similar_asset", "疑似关联资产：#{reasons.join('、')}；同号合同可包含不同资产，房号/设备编号须逐项核对。", [ candidate.public_id ]) if matches.size < 20
    end
    if match_count > matches.size
      matches << flag("additional_similarity_matches", "另有#{match_count - matches.size}条相似记录未在本页展开，请按来源编号或名称到资产台账继续核查。")
    end
    matches
  end

  def similarity_fields(asset)
    { source: normalized_text(asset.source_reference), name: normalized_text(asset.name),
      address: normalized_text(asset.address), description: normalized_text(asset.description) }
  end

  def normalized_text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.gsub(/[^\p{L}\p{N}]/, "")
  end

  def dice(left, right)
    return 0.0 if left.length < 4 || right.length < 4
    a = left.chars.each_cons(2).map(&:join).tally
    b = right.chars.each_cons(2).map(&:join).tally
    overlap = a.sum { |pair, count| [ count, b.fetch(pair, 0) ].min }
    2.0 * overlap / (left.length + right.length - 2)
  end

  def flag(code, message, related_public_ids = [])
    { "code" => code, "message" => message, "related_public_ids" => related_public_ids }
  end
end
