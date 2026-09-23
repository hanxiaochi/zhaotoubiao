class BidDraftBasis
  def self.snapshot(analysis)
    return {} unless analysis
    analysis.reload
    {
      "analysis_public_id" => analysis.public_id,
      "criteria" => analysis.criteria, "risks" => analysis.risks, "outline" => analysis.outline,
      "review_sections" => analysis.attributes.slice(*BidAnalysis::REVIEW_SECTIONS.keys),
      "scores" => analysis.bid_scores.where(active: true).order(:id).map do |score|
        score.attributes.slice("criterion", "maximum", "scoring_rule", "requires_evidence", "evidence_exception")
      end,
      "evidence" => analysis.bid_evidences.includes(:library_entry).order(:id).map do |evidence|
        usable = analysis.criteria.include?(evidence.criterion) && evidence.usable_proof?
        {
          "public_id" => evidence.public_id, "criterion" => evidence.criterion,
          "page_reference" => evidence.page_reference, "note" => evidence.note, "usable" => usable,
          "source" => usable ? evidence.source_snapshot : {},
          "warning" => usable ? nil : "该引用已失效、已过期或缺少有效附件，不得用于声明资质与业绩。"
        }
      end
    }.as_json
  end
end
