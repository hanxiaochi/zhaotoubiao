class DepartmentsController < ApplicationController
  before_action :set_department, only: %i[edit update]

  def index
    authorize Department
    @departments = Department.includes(:users, :projects).order(active: :desc, name: :asc)
  end

  def new
    @department = Department.new(active: true)
    authorize @department
  end

  def create
    @department = Department.new(department_params)
    authorize @department
    Department.transaction do
      @department.save!
      Audit::Recorder.call(action: "department.create", record: @department)
    end
    redirect_to departments_path, notice: "部门已创建。"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @department
  end

  def update
    authorize @department
    @department.with_lock do
      authorize @department
      before_data = @department.attributes
      @department.update!(department_params)
      Audit::Recorder.call(action: "department.update", record: @department, before_data: before_data)
    end
    redirect_to departments_path, notice: "部门已更新。"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  private

  def set_department
    @department = Department.find_by!(public_id: params[:id])
  end

  def department_params
    params.require(:department).permit(:code, :name, :active)
  end
end
