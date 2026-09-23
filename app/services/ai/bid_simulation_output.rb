module Ai
  class BidSimulationOutput
    def self.apply!(run)
      simulation = run.record
      attributes = attributes_for(run)
      simulation.update!(attributes)
      Audit::Recorder.call(action: "bid_simulation.ai_apply", record: simulation, after_data: { total_score: simulation.total_score, criterion_count: simulation.results.size, ai_run_public_id: run.public_id })
    end

    # The same strict parser serves read-only previews and transactional approval.
    def self.attributes_for(run)
      simulation = run.record
      data = JSON.parse(run.output)
      raise TypeError, "输出必须是对象" unless data.is_a?(Hash)
      scores = data.fetch("scores")
      raise TypeError, "scores 必须是数组" unless scores.is_a?(Array) && scores.all?(Hash)
      expected = simulation.rubric.to_h { |row| [ row.fetch("criterion_id"), row ] }
      ids = scores.map { |row| row["criterion_id"] }
      raise TypeError, "评分点缺失、重复或不属于本量表" unless ids.all?(String) && ids.size == expected.size && ids.uniq.size == ids.size && ids.sort == expected.keys.sort
      normalized = scores.map do |row|
        criterion = expected.fetch(row.fetch("criterion_id"))
        score = row.fetch("awarded")
        maximum = BigDecimal(criterion.fetch("maximum"))
        unless score.nil? || (score.is_a?(Numeric) && score.finite? && score >= 0 && score <= maximum)
          raise TypeError, "自评分超出该项范围或类型错误"
        end
        reason = string!(row.fetch("reason"))
        location = string!(row.fetch("location"))
        excerpt = row.fetch("excerpt")
        raise TypeError, "excerpt 必须是字符串" unless excerpt.is_a?(String)
        if excerpt.present? && !simulation.source_text.include?(excerpt)
          raise TypeError, "引用片段不在投标全文中"
        end
        raise TypeError, "正分建议必须引用原文片段" if score && score > 0 && excerpt.blank?
        missing = strings!(row.fetch("missing_evidence"))
        criterion.merge("awarded" => score.nil? ? nil : BigDecimal(score.to_s).round(2).to_s("F"),
          "reason" => reason, "location" => location, "excerpt" => excerpt, "missing_evidence" => missing)
      end
      total = normalized.any? { |row| row["awarded"].nil? } ? nil : normalized.sum(BigDecimal("0")) { |row| BigDecimal(row.fetch("awarded")) }
      { results: normalized, warnings: strings!(data.fetch("warnings")), total_score: total, status: "reviewed" }
    end

    def self.string!(value)
      raise TypeError, "理由和位置必须是非空字符串" unless value.is_a?(String) && value.present?
      value
    end

    def self.strings!(value)
      raise TypeError, "待核项必须是字符串数组" unless value.is_a?(Array) && value.all?(String)
      value
    end
    private_class_method :string!, :strings!
  end
end
