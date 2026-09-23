class BidScoresController < ApplicationController
  before_action :set_analysis
  before_action :set_score, only: %i[edit update]

  def new
    @score = @analysis.bid_scores.new
    load_documents
  end

  def create
    @score = @analysis.bid_scores.new
    save_score("bid_score.create")
  rescue ActiveRecord::RecordInvalid
    load_documents
    render :new, status: :unprocessable_content
  end

  def edit
    load_documents
  end

  def update
    save_score("bid_score.update")
  rescue ActiveRecord::RecordInvalid
    load_documents
    render :edit, status: :unprocessable_content
  end

  private

  def set_analysis
    @analysis = BidAnalysis.find_by!(public_id: params[:bid_analysis_id])
    authorize @analysis, :update?
  end

  def set_score
    @score = @analysis.bid_scores.find_by!(public_id: params[:id])
  end

  def load_documents
    @documents = @analysis.project.project_documents.order(:original_filename)
  end

  def save_score(action)
    @analysis.with_lock do
      authorize @analysis, :update?
      @score.reload if @score.persisted?
      before_data = @score.persisted? ? @score.attributes : nil
      @score.assign_attributes(score_params.merge(updated_by: current_user))
      @score.save!
      @analysis.update!(status: "draft", reviewed_by: nil, reviewed_at: nil, review_note: nil)
      Audit::Recorder.call(action: action, record: @score, before_data: before_data)
    end
    redirect_to @analysis, notice: "逐项评分已保存；总分按当前启用条目自动汇总，需重新人工复核。"
  end

  def score_params
    params.require(:bid_score).permit(:criterion, :maximum, :awarded, :rationale, :scoring_rule, :project_document_id, :page_reference, :requires_evidence, :evidence_exception, :active)
  end
end
