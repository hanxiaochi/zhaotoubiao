class BidEvidencesController < ApplicationController
  def create
    @analysis = BidAnalysis.find_by!(public_id: params[:bid_analysis_id])
    authorize @analysis, :update?
    source = policy_scope(LibraryEntry).find_by!(public_id: evidence_params[:library_entry_id])
    @analysis.with_lock do
      source.with_lock do
        unless source.usable?
          return redirect_to @analysis, alert: "已归档或过期资料不能新增引用。"
        end
        evidence = @analysis.bid_evidences.create!(
          evidence_params.except(:library_entry_id).merge(library_entry: source, created_by: current_user, source_snapshot: source.evidence_snapshot)
        )
        @analysis.update!(status: "draft", reviewed_by: nil, reviewed_at: nil, review_note: nil)
        Audit::Recorder.call(action: "bid_evidence.create", record: evidence)
      end
    end
    redirect_to @analysis, notice: "评分点证据已保存版本快照，分析需重新复核。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @analysis, alert: error.record.errors.full_messages.to_sentence
  end

  private

  def evidence_params
    params.require(:bid_evidence).permit(:library_entry_id, :criterion, :note, :page_reference)
  end
end
