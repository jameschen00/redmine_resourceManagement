class TaskAllocation < ActiveRecord::Base

  belongs_to :issue, :class_name => 'Issue', :foreign_key => 'issue_id'

  def self.delete_by_issue(issue)
    TaskAllocation.where(:issue_id => issue.id).each { |i| i.destroy }
  end
end
