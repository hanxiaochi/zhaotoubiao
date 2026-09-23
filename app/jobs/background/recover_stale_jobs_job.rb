module Background
  class RecoverStaleJobsJob < ApplicationJob
    queue_as :background
    STALE_AFTER = 15.minutes

    def perform(reference_time = Time.current)
      cutoff = reference_time - STALE_AFTER
      AiRun.where(status: %w[queued running], updated_at: ...cutoff).find_each do |run|
        run.with_lock do
          next unless run.status.in?(%w[queued running]) && run.updated_at < cutoff
          run.update!(status: "failed", output: "任务等待或执行超时，可能发生进程中断。请核对后重新发起；系统不会自动重复调用计费接口。")
          Audit::Recorder.call(action: "ai_run.recovered_failed", record: run)
          notify(run.requested_by, run, "AI 任务超时，请核对后重试", Rails.application.routes.url_helpers.ai_run_path(run), reference_time)
        end
      end
      ProjectDocument.where(ocr_status: %w[queued processing], updated_at: ...cutoff).find_each do |document|
        document.with_lock do
          next unless document.ocr_status.in?(%w[queued processing]) && document.updated_at < cutoff
          document.update!(ocr_status: "failed", analysis_status: "failed", ocr_attempt_token: nil,
            metadata: document.metadata.merge("ocr_error" => "任务等待或解析超时，可能发生进程中断。请重新发起解析。"))
          Audit::Recorder.call(action: "document.ocr_recovered_failed", record: document)
          notify(document.uploaded_by, document, "文件解析超时，可重新解析", Rails.application.routes.url_helpers.project_project_document_path(document.project, document), reference_time)
        end
      end
    end

    private

    def notify(user, record, title, link, reference_time)
      return unless user.active? && ProjectPolicy.new(user, record.project).show?
      Notification.deliver_once!(user: user, kind: "background.recovery", reference: record, date: reference_time.to_date, title: title, link: link)
    end
  end
end
