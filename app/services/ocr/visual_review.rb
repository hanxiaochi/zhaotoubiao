module Ocr
  module VisualReview
    KINDS = %w[red_seal_candidate signature_ink_candidate].freeze

    def self.valid?(value)
      return false unless value.is_a?(Hash) && value["status"] == "checked"
      return false unless value["signature_labels_examined"].is_a?(Integer) && value["signature_labels_examined"] >= 0
      return false unless value["omitted_candidates"].is_a?(Integer) && value["omitted_candidates"] >= 0
      return false unless value["candidates"].is_a?(Array) && value["candidates"].size <= 20

      value["candidates"].all? do |candidate|
        next false unless candidate.is_a?(Hash) && KINDS.include?(candidate["kind"]) && candidate["basis"].is_a?(String)
        box = candidate["bbox"]
        box.is_a?(Array) && box.size == 4 && box.all? { |n| n.is_a?(Numeric) && n.finite? && n.between?(0, 1) } &&
          box[0] < box[2] && box[1] < box[3]
      end
    end
  end
end
