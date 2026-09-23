module Ai
  class RunJob < ApplicationJob
    queue_as :ai

    def perform(ai_run_id)
      run = AiRun.find(ai_run_id)
      system_prompt = user_prompt = nil
      run.record.with_lock do
        run.with_lock do
          return unless run.status == "queued"
          unless run.requested_by.active? && AiRunPolicy.new(run.requested_by, run).create? && run.source_current?
            run.update!(status: "failed", output: "源数据或操作权限已变更，请重新发起任务。")
            return
          end
          context = DocumentContext.new(run.record, run.task_type)
          system_prompt, user_prompt = prompt_for(run, context)
          unless run.source_current?
            run.update!(status: "failed", output: "准备输入期间源数据已变更，请重新发起任务。")
            return
          end
          run.update!(status: "running", evidence_refs: context.evidence_refs, input_scope: context.snapshot)
        end
      end
      client = OpenaiCompatibleClient.new
      result = client.chat(system: system_prompt, user: user_prompt)
      run.with_lock do
        return unless run.status == "running"
        run.update!(
          status: "pending_review",
          provider: client.provider,
          model: client.model,
          output: result.fetch(:content),
          raw_output: result[:raw_content] || result.fetch(:content),
          input_tokens: result[:input_tokens],
          output_tokens: result[:output_tokens],
          prompt_sha256: result.fetch(:prompt_sha256) { Digest::SHA256.hexdigest("#{system_prompt}\n#{user_prompt}") }
        )
      end
    rescue OpenaiCompatibleClient::ConfigurationError, OpenaiCompatibleClient::ProviderError => error
      fail_run(run, error.message)
    rescue StandardError => error
      # Persist a safe failure state; never expose exception messages containing input or credentials.
      fail_run(run, "AI 任务执行异常，请核对后重新发起（#{error.class.name}）。")
      raise
    end

    private

    def fail_run(run, message)
      return unless run&.persisted?
      run.with_lock do
        next unless run.status.in?(%w[queued running])
        run.update!(status: "failed", output: message)
        Audit::Recorder.call(action: "ai_run.failed", record: run)
      end
    end

    def prompt_for(run, context)
      case run.task_type
      when "bid_analysis" then PromptBuilder.for_bid_analysis(run.record, context: context)
      when "claim_analysis" then PromptBuilder.for_claim_analysis(run.record, context: context)
      when "draft_document" then PromptBuilder.for_draft_document(run.record, context: context)
      when "bid_simulation" then PromptBuilder.for_bid_simulation(run.record)
      else raise OpenaiCompatibleClient::ProviderError, "暂不支持该 AI 任务类型"
      end
    end
  end
end
