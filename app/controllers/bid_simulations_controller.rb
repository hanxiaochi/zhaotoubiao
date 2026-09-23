class BidSimulationsController < ApplicationController
  before_action :set_analysis, only: %i[new create]

  def new
    @simulation = @analysis.bid_simulations.new
    authorize @simulation, :create?
    load_sources
  end

  def create
    @simulation = @analysis.bid_simulations.new(simulation_params.merge(created_by: current_user))
    authorize @simulation
    kind, public_id = params.require(:source_ref).split(":", 2)
    source = case kind
    when "generated" then @analysis.project.generated_documents.find_by!(public_id: public_id)
    when "file" then @analysis.project.project_documents.find_by!(public_id: public_id)
    else raise ActiveRecord::RecordNotFound
    end
    @analysis.with_lock do
      source.with_lock do
        @simulation.source = source
        @simulation.capture_basis
        @simulation.save!
        Audit::Recorder.call(action: "bid_simulation.create", record: @simulation, after_data: { source_public_id: source.public_id, basis_sha256: @simulation.basis_sha256 })
      end
    end
    redirect_to @simulation, notice: "已保存完整文本和评分规则快照；可发起 AI 模拟审核。"
  rescue ActiveRecord::RecordInvalid
    load_sources
    render :new, status: :unprocessable_content
  end

  def show
    @simulation = BidSimulation.find_by!(public_id: params[:id])
    authorize @simulation
    @runs = @simulation.ai_runs.order(created_at: :desc)
  end

  private

  def set_analysis
    @analysis = BidAnalysis.find_by!(public_id: params[:bid_analysis_id])
  end

  def load_sources
    @sources = @analysis.project.generated_documents.where.not(status: "archived").map { |d| [ "文稿：#{d.title}", "generated:#{d.public_id}" ] }
    @sources += @analysis.project.project_documents.where(ocr_status: "completed").where.not(status: "archived").map { |d| [ "已解析文件：#{d.original_filename}", "file:#{d.public_id}" ] }
  end

  def simulation_params
    params.require(:bid_simulation).permit(:title, :confirmed_complete)
  end
end
