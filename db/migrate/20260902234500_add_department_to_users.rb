class AddDepartmentToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :department, foreign_key: true, index: true
  end
end
