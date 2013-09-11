class TaskAllocation < ActiveRecord::Base

  belongs_to :issue, :class_name => 'Issue', :foreign_key => 'issue_id'

end
