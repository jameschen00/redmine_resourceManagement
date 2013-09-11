

class UserAllocationGanttController < ApplicationController
  unloadable


  rescue_from Query::StatementInvalid, :with => :query_statement_invalid

  helper :gantt
  helper :issues
  helper :projects
  helper :queries
  helper :users #alice
  include QueriesHelper
  helper :sort
  include SortHelper
  include UsersHelper #alice
  include Redmine::Export::PDF
  require 'user_allocation_gantt'  # alice

  def show2
    @gantt = PluginResourceModule::UserAllocationGantt.new(params)
    retrieve_query
    @query.group_by = nil
    @gantt.query = @query if @query.valid?

    respond_to do |format|
      format.html do
        searched_users(params,@gantt.json_issues)
        render :action => "show2", :layout => !request.xhr?
      end
      format.csv do
        searched_users(params,@gantt.json_issues,nil)
        send_data @gantt.to_csv ,:filename => "#{Date.today}.csv"
      end
    end
  end

  # for download xlsx
  def user_allocation_gantt_xls
    @gantt = PluginResourceModule::UserAllocationGantt.new(params)
    retrieve_query
    @query.group_by = nil
    @gantt.query = @query if @query.valid?
    searched_users(params,@gantt.json_issues,nil)
    begin
      send_data @gantt.to_xls,:type=>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',:filename => "#{Date.today}.xlsx"
    rescue Exception=>e
      searched_users(params,@gantt.json_issues)
      flash.now[:error] =   'Download fails!  Please contact admin.'
      render :action => "show2", :layout => !request.xhr?
    end
  end

  def search
    @gantt = PluginResourceModule::UserAllocationGantt.new(params)
    addSubProjectToParam(params)
    retrieve_query
    @query.group_by = nil
    @gantt.query = @query if @query.valid?
    searched_users(params, @gantt.json_issues)

    respond_to do |format|
      format.json { render :json=>@gantt.to_json, :status=>"200 ok" }
    end
  end



  def show
    @gantt = PluginResourceModule::UserAllocationGantt.new(params)    # alice
    @gantt.project = @project
    retrieve_query
    @query.group_by = nil
    @gantt.query = @query if @query.valid?

    basename = (@project ? "#{@project.identifier}-" : '') + 'gantt'

    searched_users(params,@gantt.json_issues)

    respond_to do |format|
      format.html { render :action => "show", :layout => !request.xhr? }
      format.png  { send_data(@gantt.to_image, :disposition => 'inline', :type => 'image/png', :filename => "#{basename}.png") } if @gantt.respond_to?('to_image')
      format.pdf  { send_data(@gantt.to_pdf, :type => 'application/pdf', :filename => "#{basename}.pdf") }
    end
  end

  def update_task_allocation

    issue_id = -1
    if params[:resource_task_allocation] && params[:resource_task_allocation]["id"] && params[:resource_task_allocation]["allocation"] &&
        params[:resource_task_allocation]["id"].length ==  params[:resource_task_allocation]["allocation"].length

      old_sum = 0
      new_sum = 0
      a = TaskAllocation.find(params[:resource_task_allocation]["id"][0])
      issue_id = a.issue_id
      TaskAllocation.where(:issue_id=>issue_id).order(:work_date).all.each { |t| old_sum = old_sum + t.work_hour}
      begin
        params[:resource_task_allocation]["allocation"].each{|h| new_sum = new_sum + format("%.2f",h).to_f }
      rescue Exception => e
        new_sum = -1
      end

      if old_sum == new_sum
        begin
          ActiveRecord::Base.transaction do
           for i in 0..params[:resource_task_allocation]["id"].length - 1
             id = params[:resource_task_allocation]["id"][i]
             hour = params[:resource_task_allocation]["allocation"][i]
             hour = format("%.2f",hour).to_f
             new_sum = new_sum + hour
             a = TaskAllocation.find(id)
             old_sum = old_sum + a.work_hour
             a.update_attributes(:work_hour => hour)
           end
          end
        rescue Exception => database_transaction_rollback
          #json =" {'result':'error','content':\"#{database_transaction_rollback}\"}";
        end
      end
    else
      #json = '{"result":"error"}';
    end

    result={}
    issue = Issue.find(issue_id);
    result[:date_from] = issue.start_date
    result[:date_to] = issue.due_date
    result[:allocation] = TaskAllocation.where(:issue_id=>issue_id).order(:work_date).all
    result[:issue] = issue
    json = ActiveSupport::JSON.encode(result)

    respond_to do |format|
      format.json { render :json=>json, :status=>"200 ok" }
    end
  end

  def update_task
    json = "{}";
    if params[:start] && params[:end] && params[:issue_id]
      issue = Issue.find(params[:issue_id]);
      task_allocation = {}
      result = {}

      if issue && issue.leaf?
        if issue.estimated_hours > (Date.st rptime( params[:end],"%Y-%m-%d") - Date.strptime( params[:start],"%Y-%m-%d") + 1) * 8
          # keep issue the same with the original one, and skip to end
          task_allocation = TaskAllocation.where(:issue_id=>params[:issue_id]).order(:work_date).all
        else
          begin
            ActiveRecord::Base.transaction do
              journal = issue.init_journal(User.current, 'Update allocation -- Added by User Allocation Gantt. ')
              issue.start_date =  Date.strptime( params[:start],"%Y-%m-%d")
              issue.due_date = Date.strptime( params[:end],"%Y-%m-%d")
              issue.save
              task_allocation =IssueListener.reallocate(issue)
            end
          rescue Exception => database_transaction_rollback
            json =" {'message':\"#{database_transaction_rollback}\"}";
          end
        end

      else
        #json = '{"message":"no such issue"}';
      end
    else
      #json = '{"message":"param error"}';
    end

    result = {}
    result[:date_from] = issue.start_date
    result[:date_to] = issue.due_date
    result[:allocation] = task_allocation
    result[:issue] = issue
    json = ActiveSupport::JSON.encode(result);

    respond_to do |format|
      format.json { render :json=>json, :status=>"200 ok" }
    end
  end

  #alice
  private
  def searched_users(params,issues, limit = 10 )
    sort_init 'login', 'asc'
    sort_update %w(login firstname lastname mail admin created_on last_login_on)

    @limit = limit #per_page_option
    @status = params[:status] || 1

    scope = User.logged.status(@status)
    scope = scope.like(params[:name]) if params[:name].present?
    scope = scope.in_group(params[:group_id]) if params[:group_id].present?
    scope = scope.where( ["#{User.table_name}.id in (?)", issues.group_by(&:assigned_to_id).keys])# only show users who have issue

    if !limit.nil?
      @user_count = scope.count
      @user_pages = Paginator.new self, @user_count, @limit, params['page']
      @offset ||= @user_pages.current.offset
      @users =  scope.find :all,
                         :order => sort_clause,
                         :limit  =>  @limit,
                         :offset =>  @offset
    else
      @users =  scope.find :all,
                           :order => sort_clause
    end

    @gantt.users =  @users # set to gantt

    @groups = Group.all.sort
  end

  def addSubProjectToParam(params)
    if params[:v] && params[:v][ 'project_id']
      projects = Project.visible.all(
          :conditions => ["id IN (?)", params[:v]['project_id']]
      )
      ids = []
      projects.each do |p|
        ids  << p.id.to_s
        p.descendants.all.each{|sub|ids << sub.id.to_s }
      end
      params[:v][ 'project_id'] = ids
    end
  end

end
