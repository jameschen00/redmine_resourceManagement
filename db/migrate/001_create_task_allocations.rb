class CreateTaskAllocations < ActiveRecord::Migration
  def change
    create_table :task_allocations do |t|
      t.integer :id
      t.integer :issue_id
      t.date :work_date
      t.float :work_hour
    end
    add_index :task_allocations, :id
  end
end
