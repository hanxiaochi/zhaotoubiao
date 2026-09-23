module Ocr
  class SourceLabel
    def self.call(source)
      return "来源位置待核验" unless source.is_a?(Hash)
      case source["location_kind"]
      when "logical_document" then "Word 逻辑文档（排版页码待核验）"
      when "worksheet" then "工作表：#{source['sheet'].presence || source['page']}（非打印页码）"
      else source["page"].present? ? "第 #{source['page']} 页" : "来源位置待核验"
      end
    end
  end
end
