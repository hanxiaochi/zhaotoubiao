module Ocr
  class DocumentJob < ApplicationJob
    queue_as :ocr

    def perform(document_id)
      document = ProjectDocument.find(document_id)
      token = nil
      document.with_lock do
        return unless document.ocr_status == "queued" && document.status != "archived"
        token = SecureRandom.uuid
        document.update!(ocr_status: "processing", analysis_status: "processing", ocr_attempt_token: token)
      end
      result = extract(document)
      analysis = DocumentAnalyzer.call(text: result.fetch("text"), pages: result["pages"])
      document.with_lock do
        return unless document.ocr_status == "processing" && document.ocr_attempt_token == token && document.status != "archived"
        document.update!(
        ocr_text: result.fetch("text"),
        ocr_status: "completed",
        analysis_status: "pending",
        metadata: document.metadata.merge(
          "ocr_engine" => result["engine"],
          "ocr_pages" => result["pages"],
          "ocr_warnings" => result["warnings"]
        ).merge(analysis)
        )
      end
    rescue Client::ConfigurationError, Client::WorkerError, KeyError => error
      fail_document(document, token, error.message.to_s.first(200))
    rescue StandardError => error
      fail_document(document, token, "解析任务执行异常（#{error.class.name}），请重新发起。")
      raise
    end

    private

    def fail_document(document, token, message)
      return unless document&.persisted? && token
      document.with_lock do
        next unless document.ocr_status == "processing" && document.ocr_attempt_token == token
        document.update!(ocr_status: "failed", analysis_status: "failed", metadata: document.metadata.merge("ocr_error" => message))
        Audit::Recorder.call(action: "document.ocr_failed", record: document)
      end
    end

    def extract(document)
      if document.content_type.in?(%w[text/plain text/csv])
        text = document.file.download.force_encoding(Encoding::UTF_8).scrub
        return { "text" => text, "engine" => "rails-text", "pages" => [ { "page" => 1, "text" => text } ], "warnings" => [] }
      end

      document.file.blob.open do |tempfile|
        return Client.new.extract(path: tempfile.path, filename: document.original_filename, content_type: document.content_type)
      end
    end
  end
end
