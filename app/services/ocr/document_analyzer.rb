module Ocr
  class DocumentAnalyzer
    MATERIAL_PATTERNS = {
      "债权申报书" => [ /债权申报书/, /申报债权/ ],
      "主体资格证明" => [ /营业执照/, /统一社会信用代码/, /身份证明/ ],
      "合同" => [ /合同/, /协议/ ],
      "发票" => [ /发票/, /票据/ ],
      "付款凭证" => [ /付款凭证/, /银行流水/, /转账记录/, /收款凭证/ ],
      "授权委托书" => [ /授权委托书/, /委托代理人/ ],
      "证据附件" => [ /证据目录/, /附件清单/ ]
    }.freeze

    FIELD_PATTERNS = {
      "creditor_name" => /(?:债权人|申请人)(?:名称)?\s*[：:]\s*([^\n，,；;]{2,80})/,
      "unified_code" => /统一社会信用代码\s*[：:]?\s*([0-9A-Z]{18})/i,
      "contact_phone" => /(?<!\d)((?:\+?86[- ]?)?1[3-9]\d{9}|0\d{2,3}-?\d{7,8})(?!\d)/,
      "claim_amount" => /(?:申报(?:债权)?金额|债权金额)\s*[：:]?\s*(?:人民币|￥|¥)?\s*([\d,]+(?:\.\d{1,2})?)/
    }.freeze

    REVIEW_INDICATOR_PATTERNS = {
      "signature" => [ /签字/, /签名/, /签章/ ],
      "seal" => [ /盖章/, /公章/, /印章/, /加盖.{0,8}章/ ],
      "authorization" => [ /授权委托书/, /委托代理人/, /授权范围/, /授权期限/ ]
    }.freeze

    def self.call(text:, pages: [])
      new(text: text, pages: pages).call
    end

    def initialize(text:, pages: [])
      @text = text.to_s
      @pages = Array(pages)
    end

    def call
      classification, hits = classification_result
      fields = extracted_fields
      {
        "classification" => classification,
        "classification_confidence" => confidence_for(hits),
        "classification_reason" => hits.positive? ? "命中 #{hits} 个材料关键词，需人工复核" : "未命中已配置的材料关键词",
        "extracted_fields" => fields,
        "field_sources" => fields.transform_values { |value| source_for(value) },
        "review_indicators" => review_indicators
      }
    end

    private

    def classification_result
      scores = MATERIAL_PATTERNS.transform_values { |patterns| patterns.count { |pattern| @text.match?(pattern) } }
      material_type, hits = scores.max_by { |type, score| [ score, -MATERIAL_PATTERNS.keys.index(type) ] }
      hits.to_i.positive? ? [ material_type, hits ] : [ nil, 0 ]
    end

    def confidence_for(hits)
      return 0 if hits.zero?

      [ 55 + (hits * 15), 95 ].min
    end

    def extracted_fields
      FIELD_PATTERNS.each_with_object({}) do |(field, pattern), result|
        value = @text.match(pattern)&.captures&.first&.strip
        value = value.delete(",") if field == "claim_amount" && value
        result[field] = value if value.present?
      end
    end

    def source_for(value)
      page = @pages.find { |item| source_location(item["text"].to_s, value).present? }
      source_text = page&.fetch("text", "").to_s.presence || @text
      index, matched_length = source_location(source_text, value) || [ 0, value.to_s.length ]
      {
        "page" => page&.fetch("page", nil),
        "location_kind" => page&.fetch("location_kind", nil) || "physical_page",
        "sheet" => page&.fetch("sheet", nil),
        "snippet" => source_text[[ index - 24, 0 ].max, matched_length + 48].to_s.squish.first(160)
      }
    end

    def review_indicators
      REVIEW_INDICATOR_PATTERNS.transform_values do |patterns|
        page, pattern = indicator_location(patterns)
        detected = page.present? || patterns.any? { |candidate| @text.match?(candidate) }
        source_text = page&.fetch("text", "").to_s.presence || @text
        match = pattern && source_text.match(pattern)
        {
          "detected" => detected,
          "page" => page&.fetch("page", nil),
          "location_kind" => page&.fetch("location_kind", nil) || "physical_page",
          "sheet" => page&.fetch("sheet", nil),
          "confidence" => detected ? 60 : 0,
          "snippet" => match ? source_text[[ match.begin(0) - 24, 0 ].max, match[0].length + 48].to_s.squish.first(160) : nil,
          "basis" => detected ? "OCR 文本线索，不能用于鉴定真伪或法律效力" : "未发现 OCR 文本线索，不代表原件不存在"
        }
      end
    end

    def indicator_location(patterns)
      @pages.each do |page|
        pattern = patterns.find { |candidate| page.fetch("text", "").to_s.match?(candidate) }
        return [ page, pattern ] if pattern
      end
      [ nil, patterns.find { |candidate| @text.match?(candidate) } ]
    end

    def source_location(text, value)
      exact_index = text.index(value.to_s)
      return [ exact_index, value.to_s.length ] if exact_index
      return unless value.to_s.match?(/\A\d+(?:\.\d+)?\z/)

      numeric_pattern = value.to_s.chars.map do |character|
        character.match?(/\d/) ? "#{character}[,\\s]*" : Regexp.escape(character)
      end.join
      match = text.match(Regexp.new(numeric_pattern))
      [ match.begin(0), match[0].length ] if match
    end
  end
end
