require "zip"

module DocumentExport
  class DocxBuilder
    WORD_NAMESPACE = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    def self.call(document) = new(document).call

    def initialize(document)
      @document = document
    end

    def call
      Zip::OutputStream.write_buffer do |zip|
        write(zip, "[Content_Types].xml", content_types)
        write(zip, "_rels/.rels", package_relationships)
        write(zip, "word/document.xml", document_xml)
        write(zip, "word/styles.xml", styles_xml)
        write(zip, "word/numbering.xml", numbering_xml)
        write(zip, "word/_rels/document.xml.rels", document_relationships)
      end.string
    end

    private

    def write(zip, path, content)
      zip.put_next_entry(path)
      zip.write(content)
    end

    def document_xml
      Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml["w"].document("xmlns:w" => WORD_NAMESPACE) do
          xml["w"].body do
            paragraph(xml, @document.title, "Title")
            @document.content.to_s.lines(chomp: true).each do |line|
              if numbered_item?(line)
                numbered_paragraph(xml, line.sub(/\A\s*\d+[.、)]\s*/, ""))
              else
                paragraph(xml, line, heading?(line) ? "Heading1" : "Normal")
              end
            end
            xml["w"].sectPr do
              xml["w"].pgSz("w:w" => "11906", "w:h" => "16838")
              xml["w"].pgMar("w:top" => "1440", "w:right" => "1440", "w:bottom" => "1440", "w:left" => "1440", "w:header" => "720", "w:footer" => "720")
            end
          end
        end
      end.to_xml
    end

    def paragraph(xml, text, style)
      xml["w"].p do
        xml["w"].pPr { xml["w"].pStyle("w:val" => style) }
        xml["w"].r do
          xml["w"].t(text.to_s, "xml:space" => "preserve")
        end
      end
    end

    def numbered_paragraph(xml, text)
      xml["w"].p do
        xml["w"].pPr do
          xml["w"].pStyle("w:val" => "Normal")
          xml["w"].numPr do
            xml["w"].ilvl("w:val" => "0")
            xml["w"].numId("w:val" => "1")
          end
        end
        xml["w"].r { xml["w"].t(text.to_s, "xml:space" => "preserve") }
      end
    end

    def heading?(line)
      line.match?(/\A\s*(?:第[一二三四五六七八九十百]+[章节篇]|[一二三四五六七八九十]+[、.])/)
    end

    def numbered_item?(line)
      line.match?(/\A\s*\d+[.、)]\s*\S/)
    end

    def styles_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="#{WORD_NAMESPACE}">
          <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="SimSun"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:pPr><w:spacing w:after="120" w:line="360" w:lineRule="auto"/></w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="360"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style>
        </w:styles>
      XML
    end

    def content_types
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
        </Types>
      XML
    end

    def numbering_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="#{WORD_NAMESPACE}">
          <w:abstractNum w:abstractNumId="0">
            <w:multiLevelType w:val="singleLevel"/>
            <w:lvl w:ilvl="0">
              <w:start w:val="1"/>
              <w:numFmt w:val="decimal"/>
              <w:lvlText w:val="%1."/>
              <w:lvlJc w:val="left"/>
              <w:pPr><w:tabs><w:tab w:val="num" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr>
            </w:lvl>
          </w:abstractNum>
          <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
        </w:numbering>
      XML
    end

    def package_relationships
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
      XML
    end

    def document_relationships
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        </Relationships>
      XML
    end
  end
end
