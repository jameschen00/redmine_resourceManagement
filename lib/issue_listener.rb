class IssueListener < Redmine::Hook::ViewListener


  private

  def valid_to_allocate(issue)
    !issue.nil?  && !issue.start_date.nil? && !issue.due_date.nil?  && issue.tracker_id.to_s == Setting.plugin_resource['resource_task_tracker']
  end

  def IssueListener.getWorkDays(d1,d2)
    if d1 > d2
      return 0
    elsif d1 == d2
      if d1.cwday == 0 || d1.cwday == 6
        return 0
      else
        return 1
      end
    else
      date = d1
      days = 0
      while date <= d2
        if date.cwday != 7 && date.cwday != 6
          days = days + 1
        end
        date = date + 1
      end
      return days
    end
  end

  def updateParentTask(subissue)
    if subissue.parent_id.nil? || subissue.parent_id <= 0
      return
    end
    issue = Issue.find(subissue.parent_id)

    IssueListener.deleteOldAllocation(issue)
  end


  def default_estimated_hours(issue)
    8 * IssueListener.getWorkDays(issue.start_date,issue.due_date)
  end


  public
  # hooker is in /app/controllers/issues_controller.rb
  # create corresponding task allocation in db when saving new task issue
  #
  def controller_issues_new_after_save(context={})
    issue = context[:issue]
    journal = issue.init_journal(User.current, 'Add user allocation -- Added by User Allocation Gantt.')
    if valid_to_allocate(issue) && !issue.estimated_hours
      issue.estimated_hours = default_estimated_hours(issue)
      IssueListener.newAllocate(issue)
      issue.save
    elsif valid_to_allocate(issue) && issue.estimated_hours > 0
      IssueListener.newAllocate(issue)
    end
    updateParentTask(issue)
  end


  # hooker is in /app/modules/issue.rb
  # edit corresponding task allocation in db when saving editing
  #
  def controller_issues_edit_before_save(context={})
    issue = context[:issue]
    if issue.changed_attributes && (issue.changed_attributes.has_key?('start_date') ||
        issue.changed_attributes.has_key?('due_date') ||
        issue.changed_attributes.has_key?('estimated_hours')  )  ||
        issue.changed_attributes.has_key?('tracker_id')

      if valid_to_allocate(issue) && !issue.estimated_hours
        issue.estimated_hours = default_estimated_hours(issue)
        IssueListener.reallocate(issue)
        issue.save
      elsif valid_to_allocate(issue) && issue.estimated_hours > 0
        IssueListener.reallocate(issue)
      end
    end
  end

  # hooker is in /app/modules/issue.rb
  # edit corresponding task allocation in db when saving editing
  #
  def controller_issues_edit_after_save(context={})
    issue = context[:issue]
    updateParentTask(issue)
  end


  # hooker is in /app/views/issues/_form.html.erb
  # add js to control that estimated_time / 8 <= due_date - start_date while new or edit any issue
  #
  def view_issues_form_details_bottom(context={})
    issue = context[:issue]
    if issue.leaf?    # only leaf issue need validation
      return content_tag('script', "
      $('#issue-form').submit(
        function(){
          var start_date = $('#issue_start_date').val();
          var due_date = $('#issue_due_date').val();
          var estimated_hours = $('#issue_estimated_hours').val();
          if(start_date && due_date && estimated_hours){
            var start = new Date(Date.parse(start_date.replace(/-/g, '/')));
            var end = new Date(Date.parse(due_date.replace(/-/g, '/')));
            var diff = (end - start)/(3600*24*1000) + 1; // include start and end
            var hours = parseFloat(estimated_hours);
            if(isNaN(hours)){
              alert('Estimated hours is invalid!');
              return false;
            }else if(diff < 1 || hours/8 > diff ){
              alert('Estimated: '+hours+' hours, and expected finished in '+diff+' days.  Please postpone Due Date!');
              return false;
            }
          }
          if(!$(this).attr('data-submitted-plugin-resource')){
            $(this).removeAttr('data-submitted');
            $(this).attr('data-submitted-plugin-resource');
            return true;
          }
        });
      ".html_safe)
    else
      return
    end

  end

  # hooker is in /app/views/issues/builk_edit.html.erb
  # forbidden start_date and due_date edited in bulk edit if task ticket included
  #
  def view_issues_bulk_edit_details_bottom(context={})
    has_task_issue = false
    issues = context[:issues]
    issues.each do |issue|
      if !issue.nil? && issue.tracker_id && issue.tracker_id.to_s == Setting.plugin_resource['resource_task_tracker']
        has_task_issue = true
      end
    end

    if !has_task_issue
      return
    end

    return content_tag('script', "
    $( document ).ready(function() {
      $('#bulk_edit_form').submit(function(){
        var start = $('#issue_start_date').val();
        var due = $('#issue_due_date').val();
        if(start != '' || due != ''){
          alert('Please don't change Start date and Due date!');
          return false;
        }else{
          return true;
        }
      });
    });".html_safe)
  end

  #TODO delete hook




  def IssueListener.deleteOldAllocation(issue)
    TaskAllocation.where(:issue_id => issue.id).each { |i| i.delete }
  end

  # precondition: validate_to_allocate(issue) == true
  def IssueListener.reallocate(issue)

    deleteOldAllocation(issue)
    return newAllocate(issue)
  end

  # precondition: validate_to_allocate(issue) == true
  def IssueListener.newAllocate(issue)

    # re-allocate
    allocation = allocate(issue)
    # save to db
    allocation.each do |date,hour|
      t = TaskAllocation.new(:issue_id=>issue.id, :work_date=>date, :work_hour=>hour)
      t.save
    end
    return TaskAllocation.where(:issue_id=>issue.id).order(:work_date).all
  end

  # allocate total_work_hour to each date; work day has a higher priority
  def IssueListener.allocate(issue)
    allocation = {}
    total_work_hour = format("%.1f",issue.estimated_hours).to_f
    # calculate workdays
    workdays = IssueListener.getWorkDays(issue.start_date, issue.due_date)
    if workdays <= 0 || total_work_hour <= 0
      return {}
    end
    # allocate workdays
    hours = (total_work_hour / workdays ).ceil
    hours = 8 if hours > 8
    date = issue.start_date
    while date <= issue.due_date
      if total_work_hour > 0 && date.wday != 6 && date.wday != 0
        allocation[date] = hours > total_work_hour ? total_work_hour : hours
        total_work_hour = total_work_hour - hours
      else
        allocation[date] = 0
      end
      date = date + 1
    end
    #allocation work to weekends
    date = issue.start_date
    while total_work_hour > 0 && date <= issue.due_date
      if allocation[date] == 0
        hour = total_work_hour
        hour = 8 if total_work_hour >= 8
        allocation[date] = hour
        total_work_hour = total_work_hour - hour
      end
      date = date + 1
    end
    allocation
  end

end