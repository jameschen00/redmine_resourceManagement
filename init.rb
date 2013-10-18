require 'redmine'
require_dependency 'issue_listener'
require 'issue_relations_controller'

class IssueRelationsController < ApplicationController
  def create
    @relation = IssueRelation.new(params[:relation])
    @relation.issue_from = @issue
    if params[:relation] && m = params[:relation][:issue_to_id].to_s.strip.match(/^#?(\d+)$/)
      @relation.issue_to = Issue.visible.find_by_id(m[1].to_i)
    end
    saved = @relation.save
    # update task allocations
    IssueListener.controller_issue_relation_create_after_save(@relation.issue_to)
    @relation.issue_to.relations_from.each do |relation|
      IssueListener.controller_issue_relation_create_after_save(relation.issue_to)
    end

    respond_to do |format|
      format.html { redirect_to issue_path(@issue) }
      format.js {
        @relations = @issue.reload.relations.select {|r| r.other_issue(@issue) && r.other_issue(@issue).visible? }
      }
      format.api {
        if saved
          render :action => 'show', :status => :created, :location => relation_url(@relation)
        else
          render_validation_errors(@relation)
        end
      }
    end
  end


end

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


