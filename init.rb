require 'redmine'
require_dependency 'issue_listener'

Redmine::Plugin.register :resource do
  name 'Resource Management plugin'
  author 'Alice'
  description 'This is a plugin for Redmine'
  version '0.0.1'
  url 'https://github.com/aliceeee/redmine_userAllocationGantt'
  author_url ''

  # To regist to menu
  # TODO: where to add plugin menu
  #menu :application_menu, :resource, { :controller => 'user_allocation_gantt', :action => 'show2' }, :caption => 'Resources Mangement'
  #menu :application_menu, :resource_project, { :controller => 'project_status', :action => 'index' }, :caption => 'Project Status'

  #permission :project_gantt, :project_gantt

  # To make plugin configurable
  settings :default => {'empty' => true}, :partial => 'settings/resource_settings'

end
