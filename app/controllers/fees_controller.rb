class FeesController < ApplicationController
  before_action :set_project
  before_action :set_fee, only: %i[show edit update]

  def index
    authorize @project, :show?
    records = @project.fees
    records = records.where(fee_type: params[:fee_type]) if params[:fee_type].present?
    records = records.where(invoice_status: params[:invoice_status]) if params[:invoice_status].present?
    records = records.where("note LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
    records = case params[:payment_status]
    when "unpaid" then records.where(received: 0)
    when "partial" then records.where("received > 0 AND received < receivable")
    when "paid" then records.where("receivable > 0 AND received = receivable")
    when "overpaid" then records.where("received > receivable")
    else records
    end
    @total = records.count
    @totals = { "应收" => records.sum(:receivable), "已收" => records.sum(:received),
      "未收" => records.sum("CASE WHEN receivable > received THEN receivable - received ELSE 0 END"),
      "溢收" => records.sum("CASE WHEN received > receivable THEN received - receivable ELSE 0 END") }
    @page = params[:page].to_i.clamp(1, [ (@total / 30.0).ceil, 1 ].max)
    @fees = records.includes(:created_by).order(created_at: :desc, id: :desc).limit(30).offset((@page - 1) * 30)
  end

  def show
    authorize @fee
  end

  def new
    @fee = @project.fees.new(receivable: 0, received: 0, invoice_status: "not_issued")
    authorize @fee
  end

  def create
    @fee = @project.fees.new(fee_params.merge(created_by: current_user))
    authorize @fee
    Fee.transaction do
      @fee.save!
      Audit::Recorder.call(action: "fee.create", record: @fee)
    end
    redirect_to @project, notice: "收费记录已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @fee
  end

  def update
    authorize @fee
    @fee.with_lock do
      before_data = @fee.attributes
      @fee.update!(fee_params)
      Audit::Recorder.call(action: "fee.update", record: @fee, before_data: before_data)
    end
    redirect_to project_fee_path(@project, @fee), notice: "收费记录已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_project
    @project = Project.find_by!(public_id: params[:project_id])
  end

  def set_fee
    @fee = @project.fees.find_by!(public_id: params[:id])
  end

  def fee_params
    params.require(:fee).permit(:fee_type, :receivable, :received, :received_on, :invoice_status, :note)
  end
end
