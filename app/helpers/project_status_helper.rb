module ProjectStatusHelper
  include ProjectsHelper
  # Returns the issues that belong to +project+
  def project_issues(project)
    Issue.where(:project_id=>project.id)
  end

  def project_nonversion_issues(project,issues)
    issues.select {|i| i.fixed_version.nil?}
  end

  # Returns the distinct versions of the issues that belong to +project+
  def project_versions(project,issues)
    issues.collect(&:fixed_version).compact.uniq
  end

  # Returns the issues that belong to +project+ and are assigned to +version+
  def version_issues(project, version,issues)
    issues.select {|issue| issue.fixed_version == version}
  end


  def current_issue?(issue,today)
    return (issue.start_date && issue.due_date&& issue.start_date <= today && issue.due_date >= today && !issue.closed?) || (issue.start_date && issue.due_date.nil? && issue.start_date <= today && !issue.closed?)
  end

  def render_issue (issue,today)
    style = ''
    if current_issue?(issue,today)
      style = 'highlight_yellow'
    elsif issue.due_date && issue.due_date < today
      style = 'grey_italic'
    end
    return "<div style='text-align: center;' class='#{style}'>
                  <span>
                    #{link_to_issue(issue,:subject => false, :tracker => false )}
                    &nbsp;
                    #{issue.start_date }
                    #{'0000-00-00' if issue.start_date.nil?}
                    ~
                    #{issue.due_date}
                    #{'0000-00-00' if issue.due_date.nil?}
                  </span>
                </div>".html_safe
  end
end
