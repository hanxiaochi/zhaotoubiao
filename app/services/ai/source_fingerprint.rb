module Ai
  class SourceFingerprint
    def self.call(record)
      record.reload
      documents = record.project.project_documents.order(:id).map(&:attributes)
      related = case record
      when Claim then record.claim_materials.order(:id).map(&:attributes)
      when BidAnalysis then { evidence: record.bid_evidences.order(:id).map(&:attributes), scores: record.bid_scores.order(:id).map(&:attributes) }
      when BidSimulation then { current_basis: record.basis_fingerprint }
      when GeneratedDocument then BidDraftBasis.snapshot(record.bid_analysis)
      else []
      end
      payload = { record: record.attributes, project: record.project.reload.attributes, documents: documents, related: related }
      Digest::SHA256.hexdigest(canonical(payload).to_json)
    end

    def self.canonical(value)
      case value
      when Hash then value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
    private_class_method :canonical
  end
end
