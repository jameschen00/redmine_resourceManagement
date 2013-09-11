class ProjectStatusController < ApplicationController
  unloadable



  def index
    @lines = Array.new
    @project_open = Project.active
    workload = [] # calculate hours for project only(not including versions)

    Project.project_tree(@project_open) do |proj, level|
      # all issues in project
      issuelist = project_issues(proj)

      # non-version issues are counted into project
      line = {:level=>level,:project=>proj}
      noversion_issues = project_nonversion_issues(proj,issuelist)
      addSpecifiedIssues(line, noversion_issues)
      calculateProjectHours(proj, level,calculateTotalEstimatedHours(issuelist),workload)
      @lines.push(line)

      # versions' issues are counted into project
      line = Array.new
      versions = project_versions(proj,issuelist)
      versions.each do |version|
        line = {:level=>level+1,:version=>version}
        issues_of_version = version_issues(proj,version,issuelist)
        addSpecifiedIssues(line, issues_of_version)
        line[:workload] = calculateTotalEstimatedHours(issues_of_version)
        @lines.push(line)
      end
    end
    setWordloadToLines(workload)
  end


  private

  def setWordloadToLines(workload)
    @lines.each do |line|
      workload.each do |w|
        if line[:project] && line[:project].id == w[:project_id]
          line[:workload] = w[:hours]
        end
      end
    end
  end

  def calculateProjectHours(project, level,hours,workload)
    if workload.length > 0
      i =  workload.length - 1
      level_pointer = level - 1 # to store last level
      max = 99999
      while i >= 0 && max >=0
        if workload[i][:level] == level_pointer
          workload[i][:hours] =  workload[i][:hours] + hours
          level_pointer = level_pointer - 1
          if workload[i][:level] == 0    # if this is the root of project
            break
          end
        end
        i = i-1
        max = max - 1
      end
    end

    workload.push({:hours => hours,:level=>level,:project_id=>project.id})
  end

  def calculateTotalEstimatedHours(issuelist)
    hours = 0
    issuelist.each do |issue|
      hours = hours + issue.estimated_hours if issue.leaf? && !issue.estimated_hours.nil?
    end
    hours
  end

  def addSpecifiedIssues( line, noversion_issues)
    currentTracker = ''
    Setting.plugin_resource["resource_project_status_tracker"].each do |trackerId|
      line[trackerId] = []
      noversion_issues.each do |issue|
        if issue.tracker_id.to_s == trackerId && current_issue?(issue, Date.today)
          currentTracker = currentTracker + ', ' if currentTracker.length > 0
          currentTracker = currentTracker + Tracker.find(trackerId).name
        end
        if issue.tracker_id.to_s == trackerId
          line[trackerId].push(issue)
        end
      end
    end
    line[:currentTracker] = ', ' if !line[:currentTracker].nil?
    line[:currentTracker] = line[:currentTracker] + currentTracker if !line[:currentTracker].nil?
    line[:currentTracker] = currentTracker if line[:currentTracker].nil?
  end

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

end
