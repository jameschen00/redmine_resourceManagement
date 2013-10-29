require 'csv'
require 'axlsx'

module PluginResourceModule
    # Simple class to handle gantt chart data
    class UserAllocationGantt
      include ERB::Util
      include Redmine::I18n
      include Redmine::Utils::DateCalculation

      # :nodoc:
      # Some utility methods for the PDF export
      class PDF
        MaxCharactorsForSubject = 45
        TotalWidth = 280
        LeftPaneWidth = 100

        def self.right_pane_width
          TotalWidth - LeftPaneWidth
        end
      end

      attr_reader :year_from, :month_from, :date_from, :date_to, :zoom, :months, :truncated, :max_rows
      attr_accessor :query
      attr_accessor :project
      attr_accessor :view
      attr_accessor :users #alice search result of user

      def initialize(options={})
        options = options.dup
        if options[:year] && options[:year].to_i >0
          @year_from = options[:year].to_i
          if options[:month] && options[:month].to_i >=1 && options[:month].to_i <= 12
            @month_from = options[:month].to_i
          else
            @month_from = 1
          end
        else
          @month_from ||= Date.today.month
          @year_from ||= Date.today.year
        end
        zoom = (options[:zoom] || User.current.pref[:gantt_zoom]).to_i
        @zoom = (zoom > 0 && zoom < 5) ? zoom : 2
        months = (options[:months] || User.current.pref[:gantt_months]).to_i
        @months = (months > 0 && months < 25) ? months : 6
        # Save gantt parameters as user preference (zoom and months count)
        # alice start: fixed zooom
        #if (User.current.logged? && (@zoom != User.current.pref[:gantt_zoom] ||
        #    @months != User.current.pref[:gantt_months]))
        #  User.current.pref[:gantt_zoom], User.current.pref[:gantt_months] = @zoom, @months
        #  User.current.preference.save
        #end
        @zoom =  5 #constant
        # alice end
        @date_from = Date.civil(@year_from, @month_from, 1)
        @date_to = (@date_from >> @months) - 1
        @subjects = ''
        @lines = ''
        @number_of_rows = nil
        @issue_ancestors = []
        @truncated = false
        if options.has_key?(:max_rows)
          @max_rows = options[:max_rows]
        else
          @max_rows = Setting.gantt_items_limit.blank? ? nil : Setting.gantt_items_limit.to_i
        end
        @users = {}     # alice
      end


      def common_params
        { :controller => 'user_allocation_gantt', :action => 'show2', :project_id => @project }
      end

      def params
        common_params.merge({:zoom => zoom, :year => year_from,
                             :month => month_from, :months => months})
      end

      def params_previous
        common_params.merge({:year => (date_from << months).year,
                             :month => (date_from << months).month,
                             :zoom => zoom, :months => months})
      end

      def params_next
        common_params.merge({:year => (date_from >> months).year,
                             :month => (date_from >> months).month,
                             :zoom => zoom, :months => months})
      end

      # Returns the number of rows that will be rendered on the Gantt chart
      def number_of_rows
        return @number_of_rows if @number_of_rows
        rows = projects.inject(0) {|total, p| total += number_of_rows_on_project(p)}
        rows > @max_rows ? @max_rows : rows
        rows
      end

      # Returns the number of rows that will be used to list a project on
      # the Gantt chart.  This will recurse for each subproject.
      def number_of_rows_on_project(project)
        return 0 unless projects.include?(project)
        count = 1
        count += project_issues(project).size
        count += project_versions(project).size
        count
      end

      # Renders the subjects of the Gantt chart, the left side.
      def subjects(options={})
        render(options.merge(:only => :subjects)) unless @subjects_rendered
        @subjects
      end

      # Renders the lines of the Gantt chart, the right side
      def lines(options={})
        render(options.merge(:only => :lines)) unless @lines_rendered
        @lines
      end


      # Returns issues that will be rendered
      def issues
        @issues ||= @query.issues(
            :include => [:assigned_to, :tracker, :priority, :category, :fixed_version],
            :order => "#{Project.table_name}.lft ASC, #{Issue.table_name}.id ASC",
            :limit => @max_rows
        )
      end

      # Return all the project nodes that will be displayed
      def projects
        return @projects if @projects
        ids = issues.collect(&:project).uniq.collect(&:id)
        if ids.any?
          # All issues projects and their visible ancestors
          @projects = Project.visible.all(
              :joins => "LEFT JOIN #{Project.table_name} child ON #{Project.table_name}.lft <= child.lft AND #{Project.table_name}.rgt >= child.rgt",
              :conditions => ["child.id IN (?)", ids],
              :order => "#{Project.table_name}.lft ASC"
          ).uniq
        else
          @projects = []
        end
      end

      # Returns the issues that belong to +project+
      def project_issues(project)
        @issues_by_project ||= issues.group_by(&:project)
        @issues_by_project[project] || []
      end

      #alice
      def user_issues(user)
        @issues_by_user ||= issues.group_by(&:assigned_to)
        @issues_by_user[user] || []
      end

      # Returns the distinct versions of the issues that belong to +project+
      def project_versions(project)
        project_issues(project).collect(&:fixed_version).compact.uniq
      end

      # Returns the issues that belong to +project+ and are assigned to +version+
      def version_issues(project, version)
        project_issues(project).select {|issue| issue.fixed_version == version}
      end

      # alice
      def json_issues
        Setting.plugin_resource['resource_task_tracker'] = [] if Setting.plugin_resource['resource_task_tracker'].nil?
        @json_issues = @query.issues(
            :include => [:assigned_to, :tracker, :priority, :category, :fixed_version],
            :conditions => ["start_date < ? and  due_date>? and tracker_id in (?)", @date_to, @date_from, Setting.plugin_resource['resource_task_tracker'] ],
            :order => "#{Project.table_name}.lft ASC, #{Issue.table_name}.id ASC",
            :limit => @max_rows
        ) if !@query.nil?
        @json_issues
      end

      # alice
      def prepare_data
        result = {}
        result[:date_from] = @date_from
        result[:date_to] = @date_to
        result[:users] = []

        issues = @json_issues || []
        issues.each do |i|
          i[:project_name] = i.project.name
          i[:project_identifier] = i.project.identifier
        end

        #search issues of this user
        issues_by_user ||= issues.group_by(&:assigned_to)
        this_issues = issues_by_user[nil] || []
        sort_issues!(this_issues)
        task_allocation_of_issues = task_allocation_of_issues(this_issues)        #allocation for each issue
        total_task_allocation = total_task_allocation(task_allocation_of_issues)   #add up all allocated work hours
        allocation = total_task_allocation_in_calender(total_task_allocation,@date_from,@date_to)
        result[:users].push({:name=>'Unassigned',:id=>'0',:url=> '',:status=>1,:issues=>this_issues,:task_allocation_of_issues=>task_allocation_of_issues,:allocation=>allocation})

        for user in @users
          #search issues of this user
          this_issues = issues_by_user[user] || []
          sort_issues!(this_issues)

          task_allocation_of_issues = task_allocation_of_issues(this_issues)        #allocation for each issue
          total_task_allocation = total_task_allocation(task_allocation_of_issues)   #add up all allocated work hours
          allocation = total_task_allocation_in_calender(total_task_allocation,@date_from,@date_to)
          if(total_task_allocation && total_task_allocation.length > 0)
            result[:users].push({:name=>user.lastname+' '+user.firstname,:id=>user.id,:url=> "users/#{user.id}",:status=>user.status,:allocation=>allocation,:issues=>this_issues,:task_allocation_of_issues=>task_allocation_of_issues})
          end
        end
        result
      end

      def to_json
        result = prepare_data
        ActiveSupport::JSON.encode(result)
      end


      def render(options={})
        options = {:top => 0, :top_increment => 30,
                   :indent_increment => 20, :render => :subject,
                   :format => :html}.merge(options)
        indent = options[:indent] || 4
        @subjects = '' unless options[:only] == :lines
        @lines = '' unless options[:only] == :subjects
        @number_of_rows = 0
        #alice start
        #Project.project_tree(projects) do |project, level|
        #  options[:indent] = indent + level * options[:indent_increment]
        #  render_project(project, options)
        #  break if abort?
        #end
        options[:indent] = indent
        render_user(nil,options)
        @users.each { |user|
          options[:indent] = indent
          render_user(user, options)
          break if abort?
        }
        #alice end
        @subjects_rendered = true unless options[:only] == :lines
        @lines_rendered = true unless options[:only] == :subjects
        render_end(options)
      end

      # return a hash like{issue_id => allocation_obj_list}
      def task_allocation_of_issues(issues)
        task_allocation = {}
        if issues
          issues.each do |issue|
            list = TaskAllocation.where(:issue_id=>issue.id).order(:work_date).all
            task_allocation[issue.id] = list
          end
        end
        task_allocation
      end
      # return a hash like{date => work_hour}
      def total_task_allocation(task_allocation)
        total_allocation = {}
        task_allocation.each do | issue_id ,allocations|
          if allocations
            allocations.each do |a|
              if !total_allocation[a.work_date]
                total_allocation[a.work_date] = a.work_hour
              else
                total_allocation[a.work_date] = total_allocation[a.work_date] + a.work_hour
              end
            end
          end
        end
        total_allocation
      end
      # return
      def total_task_allocation_in_calender(total_task_allocation,from, to)
        result = []
        if total_task_allocation && from && to && from.instance_of?(Date) && to.instance_of?(Date)
          date = from
          while date <= to
            if total_task_allocation[date]
              result << total_task_allocation[date]
            else
              result << 0
            end
            date = date + 1 #next day
          end
        end
        result
      end

      # alice
      def render_user(user, options={})
        subject_for_user(user, options) unless options[:only] == :lines

        return if abort?
        issues = user_issues(user)
        sort_issues!(issues)

        task_allocation = task_allocation_of_issues(issues)
        total_allocation = total_task_allocation(task_allocation)
        line_for_user(user, options, total_allocation) unless options[:only] == :subjects

        options[:top] += options[:top_increment]
        options[:indent] += options[:indent_increment]
        @number_of_rows += 1
        if issues
          render_issues(issues, options)
          return if abort?
        end

        # Remove indent to hit the next sibling
        options[:indent] -= options[:indent_increment]
      end

      def render_project(project, options={})
        subject_for_project(project, options) unless options[:only] == :lines
        line_for_project(project, options) unless options[:only] == :subjects
        options[:top] += options[:top_increment]
        options[:indent] += options[:indent_increment]
        @number_of_rows += 1
        return if abort?
        issues = project_issues(project).select {|i| i.fixed_version.nil?}
        sort_issues!(issues)
        if issues
          render_issues(issues, options)
          return if abort?
        end
        versions = project_versions(project)
        versions.each do |version|
          render_version(project, version, options)
        end
        # Remove indent to hit the next sibling
        options[:indent] -= options[:indent_increment]
      end

      def render_issues(issues, options={})
        @issue_ancestors = []
        issues.each do |i|
          if Setting.plugin_resource['resource_task_tracker'].is_a?(Array) &&
              Setting.plugin_resource['resource_task_tracker'].include?(i.tracker_id) #alice: skip drawing trackers that doesn't match setting
            next
          end
          subject_for_issue(i, options) unless options[:only] == :lines
          line_for_issue(i, options) unless options[:only] == :subjects
          options[:top] += options[:top_increment]
          @number_of_rows += 1
          break if abort?
        end
        options[:indent] -= (options[:indent_increment] * @issue_ancestors.size)
      end

      def render_version(project, version, options={})
        # Version header
        subject_for_version(version, options) unless options[:only] == :lines
        line_for_version(version, options) unless options[:only] == :subjects
        options[:top] += options[:top_increment]
        @number_of_rows += 1
        return if abort?
        issues = version_issues(project, version)
        if issues
          sort_issues!(issues)
          # Indent issues
          options[:indent] += options[:indent_increment]
          render_issues(issues, options)
          options[:indent] -= options[:indent_increment]
        end
      end

      def render_end(options={})
        case options[:format]
          when :pdf
            options[:pdf].Line(15, options[:top], PDF::TotalWidth, options[:top])
        end
      end

      def subject_for_project(project, options)
        case options[:format]
          when :html
            html_class = ""
            html_class << 'icon icon-projects '
            html_class << (project.overdue? ? 'project-overdue' : '')
            s = view.link_to_project(project).html_safe
            subject = view.content_tag(:span, s,
                                       :class => html_class).html_safe
            html_subject(options, subject, :css => "project-name")
          when :image
            image_subject(options, project.name)
          when :pdf
            pdf_new_page?(options)
            pdf_subject(options, project.name)
        end
      end

      def subject_for_user(user, options)
        case options[:format]
          when :html
            html_class = ""
            html_class << 'icon icon-projects '

            s = 'Unassigned'.html_safe
            s = view.link_to_user(user).html_safe if !user.nil?
            subject = view.content_tag(:span, s,
                                       :class => html_class).html_safe
            html_subject(options, subject, :css => "project-name")
        end
      end

      def line_for_project(project, options)
        # Skip versions that don't have a start_date or due date
        if project.is_a?(Project) && project.start_date && project.due_date
          options[:zoom] ||= 1
          options[:g_width] ||= (self.date_to - self.date_from + 1) * options[:zoom]
          coords = coordinates(project.start_date, project.due_date, nil, options[:zoom])
          label = h(project)
          case options[:format]
            when :html
              html_task(options, coords, :css => "project task", :label => label, :markers => true)
            when :image
              image_task(options, coords, :label => label, :markers => true, :height => 3)
            when :pdf
              pdf_task(options, coords, :label => label, :markers => true, :height => 0.8)
          end
        else
          ActiveRecord::Base.logger.debug "Gantt#line_for_project was not given a project with a start_date"
          ''
        end
      end

      def line_for_user(user, options, total_allocation)

        options[:zoom] ||= 1
        options[:g_width] ||= (self.date_to - self.date_from + 1) * options[:zoom]
        coords = coordinates(@date_from,@date_to, nil, options[:zoom])
        label = h(project)
        case options[:format]
          when :html
            html_user_back(options, coords, :css => 'resource_personal_allocation_back', :label => label, :markers => true)
            for date,hour in total_allocation
              coords = coordinates(date, date, nil, options[:zoom])
              html_user_allocation(options, coords, :css => 'resource_task_allocation', :label => label, :markers => true,
                                   :date=>date,:hour=>hour)
            end
        end

      end

      def subject_for_version(version, options)
        case options[:format]
          when :html
            html_class = ""
            html_class << 'icon icon-package '
            html_class << (version.behind_schedule? ? 'version-behind-schedule' : '') << " "
            html_class << (version.overdue? ? 'version-overdue' : '')
            s = view.link_to_version(version).html_safe
            subject = view.content_tag(:span, s,
                                       :class => html_class).html_safe
            html_subject(options, subject, :css => "version-name")
          when :image
            image_subject(options, version.to_s_with_project)
          when :pdf
            pdf_new_page?(options)
            pdf_subject(options, version.to_s_with_project)
        end
      end

      def line_for_version(version, options)
        # Skip versions that don't have a start_date
        if version.is_a?(Version) && version.start_date && version.due_date
          options[:zoom] ||= 1
          options[:g_width] ||= (self.date_to - self.date_from + 1) * options[:zoom]
          coords = coordinates(version.start_date,
                               version.due_date, version.completed_pourcent,
                               options[:zoom])
          label = "#{h version} #{h version.completed_pourcent.to_i.to_s}%"
          label = h("#{version.project} -") + label unless @project && @project == version.project
          case options[:format]
            when :html
              html_task(options, coords, :css => "version task", :label => label, :markers => true)
            when :image
              image_task(options, coords, :label => label, :markers => true, :height => 3)
            when :pdf
              pdf_task(options, coords, :label => label, :markers => true, :height => 0.8)
          end
        else
          ActiveRecord::Base.logger.debug "Gantt#line_for_version was not given a version with a start_date"
          ''
        end
      end

      def subject_for_issue(issue, options)
        while @issue_ancestors.any? && !issue.is_descendant_of?(@issue_ancestors.last)
          @issue_ancestors.pop
          options[:indent] -= options[:indent_increment]
        end
        output = case options[:format]
                   when :html
                     css_classes = ''
                     css_classes << ' issue-overdue' if issue.overdue?
                     css_classes << ' issue-behind-schedule' if issue.behind_schedule?
                     css_classes << ' icon icon-issue' unless Setting.gravatar_enabled? && issue.assigned_to
                     s = "".html_safe
                     if issue.assigned_to.present?
                       assigned_string = l(:field_assigned_to) + ": " + issue.assigned_to.name
                       s << view.avatar(issue.assigned_to,
                                        :class => 'gravatar icon-gravatar',
                                        :size => 10,
                                        :title => assigned_string).to_s.html_safe
                     end

                     #alice start
                     s << view.content_tag(:span,
                                           view.link_to_issue(issue).html_safe,
                                          :class => '').html_safe
                     s << view.link_to_project(issue.project).html_safe
                     s << "(#{issue.estimated_hours})" if !issue.estimated_hours.nil?  # alice: show issue's estimated hour
                     #alice end
                     subject = view.content_tag(:span, s, :class => css_classes).html_safe
                     html_subject(options, subject, :css => "issue-subject",
                                  :title => issue.subject) + "\n"
                   when :image
                     image_subject(options, issue.subject)
                   when :pdf
                     pdf_new_page?(options)
                     pdf_subject(options, issue.subject)
                 end
        unless issue.leaf?
          @issue_ancestors << issue
          options[:indent] += options[:indent_increment]
        end
        output
      end

      def line_for_issue(issue, options)
        # Skip issues that don't have a due_before (due_date or version's due_date)
        if issue.is_a?(Issue) && issue.due_before
          coords = coordinates(issue.start_date, issue.due_before, issue.done_ratio, options[:zoom])
          label = "#{issue.status.name} #{issue.done_ratio}%"
          case options[:format]
            when :html
              html_task(options, coords,
                        :css => "task " + (issue.leaf? ? 'leaf' : 'parent'),
                        :label => label, :issue => issue,
                        :markers => !issue.leaf?,
                        :allocation => TaskAllocation.where(:issue_id=>issue.id).order(:work_date).all)
            when :image
              image_task(options, coords, :label => label)
            when :pdf
              pdf_task(options, coords, :label => label)
          end
        else
          ActiveRecord::Base.logger.debug "GanttHelper#line_for_issue was not given an issue with a due_before"
          ''
        end
      end

      # Generates a gantt image
      # Only defined if RMagick is avalaible
      def to_image(format='PNG')
        date_to = (@date_from >> @months) - 1
        show_weeks = @zoom > 1
        show_days = @zoom > 2
        subject_width = 400
        header_height = 18
        # width of one day in pixels
        zoom = @zoom * 2
        g_width = (@date_to - @date_from + 1) * zoom
        g_height = 20 * number_of_rows + 30
        headers_height = (show_weeks ? 2 * header_height : header_height)
        height = g_height + headers_height
        imgl = Magick::ImageList.new
        imgl.new_image(subject_width + g_width + 1, height)
        gc = Magick::Draw.new
        gc.font = Redmine::Configuration['rmagick_font_path'] || ""
        # Subjects
        gc.stroke('transparent')
        subjects(:image => gc, :top => (headers_height + 20), :indent => 4, :format => :image)
        # Months headers
        month_f = @date_from
        left = subject_width
        @months.times do
          width = ((month_f >> 1) - month_f) * zoom
          gc.fill('white')
          gc.stroke('grey')
          gc.stroke_width(1)
          gc.rectangle(left, 0, left + width, height)
          gc.fill('black')
          gc.stroke('transparent')
          gc.stroke_width(1)
          gc.text(left.round + 8, 14, "#{month_f.year}-#{month_f.month}")
          left = left + width
          month_f = month_f >> 1
        end
        # Weeks headers
        if show_weeks
          left = subject_width
          height = header_height
          if @date_from.cwday == 1
            # date_from is monday
            week_f = date_from
          else
            # find next monday after date_from
            week_f = @date_from + (7 - @date_from.cwday + 1)
            width = (7 - @date_from.cwday + 1) * zoom
            gc.fill('white')
            gc.stroke('grey')
            gc.stroke_width(1)
            gc.rectangle(left, header_height, left + width, 2 * header_height + g_height - 1)
            left = left + width
          end
          while week_f <= date_to
            width = (week_f + 6 <= date_to) ? 7 * zoom : (date_to - week_f + 1) * zoom
            gc.fill('white')
            gc.stroke('grey')
            gc.stroke_width(1)
            gc.rectangle(left.round, header_height, left.round + width, 2 * header_height + g_height - 1)
            gc.fill('black')
            gc.stroke('transparent')
            gc.stroke_width(1)
            gc.text(left.round + 2, header_height + 14, week_f.cweek.to_s)
            left = left + width
            week_f = week_f + 7
          end
        end
        # Days details (week-end in grey)
        if show_days
          left = subject_width
          height = g_height + header_height - 1
          wday = @date_from.cwday
          (date_to - @date_from + 1).to_i.times do
            width =  zoom
            gc.fill(non_working_week_days.include?(wday) ? '#eee' : 'white')
            gc.stroke('#ddd')
            gc.stroke_width(1)
            gc.rectangle(left, 2 * header_height, left + width, 2 * header_height + g_height - 1)
            left = left + width
            wday = wday + 1
            wday = 1 if wday > 7
          end
        end
        # border
        gc.fill('transparent')
        gc.stroke('grey')
        gc.stroke_width(1)
        gc.rectangle(0, 0, subject_width + g_width, headers_height)
        gc.stroke('black')
        gc.rectangle(0, 0, subject_width + g_width, g_height + headers_height - 1)
        # content
        top = headers_height + 20
        gc.stroke('transparent')
        lines(:image => gc, :top => top, :zoom => zoom,
              :subject_width => subject_width, :format => :image)
        # today red line
        if Date.today >= @date_from and Date.today <= date_to
          gc.stroke('red')
          x = (Date.today - @date_from + 1) * zoom + subject_width
          gc.line(x, headers_height, x, headers_height + g_height - 1)
        end
        gc.draw(imgl)
        imgl.format = format
        imgl.to_blob
      end if Object.const_defined?(:Magick)

      def to_pdf
        pdf = ::Redmine::Export::PDF::ITCPDF.new(current_language)
        pdf.SetTitle("#{l(:label_gantt)} #{project}")
        pdf.alias_nb_pages
        pdf.footer_date = format_date(Date.today)
        pdf.AddPage("L")
        pdf.SetFontStyle('B', 12)
        pdf.SetX(15)
        pdf.RDMCell(PDF::LeftPaneWidth, 20, project.to_s)
        pdf.Ln
        pdf.SetFontStyle('B', 9)
        subject_width = PDF::LeftPaneWidth
        header_height = 5
        headers_height = header_height
        show_weeks = false
        show_days = false
        if self.months < 7
          show_weeks = true
          headers_height = 2 * header_height
          if self.months < 3
            show_days = true
            headers_height = 3 * header_height
          end
        end
        g_width = PDF.right_pane_width
        zoom = (g_width) / (self.date_to - self.date_from + 1)
        g_height = 120
        t_height = g_height + headers_height
        y_start = pdf.GetY
        # Months headers
        month_f = self.date_from
        left = subject_width
        height = header_height
        self.months.times do
          width = ((month_f >> 1) - month_f) * zoom
          pdf.SetY(y_start)
          pdf.SetX(left)
          pdf.RDMCell(width, height, "#{month_f.year}-#{month_f.month}", "LTR", 0, "C")
          left = left + width
          month_f = month_f >> 1
        end
        # Weeks headers
        if show_weeks
          left = subject_width
          height = header_height
          if self.date_from.cwday == 1
            # self.date_from is monday
            week_f = self.date_from
          else
            # find next monday after self.date_from
            week_f = self.date_from + (7 - self.date_from.cwday + 1)
            width = (7 - self.date_from.cwday + 1) * zoom-1
            pdf.SetY(y_start + header_height)
            pdf.SetX(left)
            pdf.RDMCell(width + 1, height, "", "LTR")
            left = left + width + 1
          end
          while week_f <= self.date_to
            width = (week_f + 6 <= self.date_to) ? 7 * zoom : (self.date_to - week_f + 1) * zoom
            pdf.SetY(y_start + header_height)
            pdf.SetX(left)
            pdf.RDMCell(width, height, (width >= 5 ? week_f.cweek.to_s : ""), "LTR", 0, "C")
            left = left + width
            week_f = week_f + 7
          end
        end
        # Days headers
        if show_days
          left = subject_width
          height = header_height
          wday = self.date_from.cwday
          pdf.SetFontStyle('B', 7)
          (self.date_to - self.date_from + 1).to_i.times do
            width = zoom
            pdf.SetY(y_start + 2 * header_height)
            pdf.SetX(left)
            pdf.RDMCell(width, height, day_name(wday).first, "LTR", 0, "C")
            left = left + width
            wday = wday + 1
            wday = 1 if wday > 7
          end
        end
        pdf.SetY(y_start)
        pdf.SetX(15)
        pdf.RDMCell(subject_width + g_width - 15, headers_height, "", 1)
        # Tasks
        top = headers_height + y_start
        options = {
            :top => top,
            :zoom => zoom,
            :subject_width => subject_width,
            :g_width => g_width,
            :indent => 0,
            :indent_increment => 5,
            :top_increment => 5,
            :format => :pdf,
            :pdf => pdf
        }
        render(options)
        pdf.Output
      end

      # alice
      # to csv
      #
      def to_csv(options={})
        data = prepare_data
        CSV.generate(options) do |csv|
          # Title line
          csv << ["\xEF\xBB\xBF"]
          # date
          month_line =  ['','','','']
          date_line =  ['','','','']
          weedday_line = ['','','','']
          d = @date_from
          while d <= @date_to
            month_line << d.strftime("%b") if d.day == 1
            month_line << '' if d.day != 1
            date_line << d.day
            weedday_line << d.strftime("%a")
            d = d + 1
          end
          csv << month_line
          csv << date_line
          csv << weedday_line
          # for each user
          data[:users].each  do |user|
            # add user line
            user_line = ["#{user[:name]}", '','','']
            user_line = user_line + user[:allocation] if user[:allocation]
            csv << user_line
            # add issue
            parent_issue_stack = []
            user[:issues].each do |issue|
              # issue stack -- for indent calculation
               if(issue.id != issue.parent_id)  # is not leaf
                 while parent_issue_stack[parent_issue_stack.length-1] != issue.parent_id
                     parent_issue_stack.pop();
                    if parent_issue_stack.length == 0
                      break
                    end
                 end
                parent_issue_stack.push(issue.id);
               else    # is leaf
                 parent_issue_stack = new Array();
                 parent_issue_stack.push(issue.id);
               end
              #issue line
              issue_line = ['',">"*parent_issue_stack.length<<issue.subject, issue.project_name, "#{issue.estimated_hours} h"]
              issue_line = issue_line + [''] * (issue.start_date - @date_from) if issue.start_date > @date_from
              user[:task_allocation_of_issues][issue.id].each do |a|
                if a.work_date >= @date_from && a.work_date <= @date_to
                  issue_line << a.work_hour
                end
              end
              csv << issue_line
            end
          end
        end
      end

      # alice
      # to xls
      #
      def to_xls(options={})
        data = prepare_data

        p = Axlsx::Package.new
        wb = p.workbook
        wb.add_worksheet(:name => "#{@date_from}~#{@date_to}") do |sheet|
          style_date = sheet.styles.add_style :alignment=>{:horizontal => :center},
                                              :b=>true,
                                              :sz=>10,
                                              :bg_color => 'DDD9C4',
                                              :border => { :color => 'ff', :style => :thin}
          style_week = sheet.styles.add_style :alignment=>{:horizontal => :center},
                                              :b=>true,
                                              :sz=>10,
                                              :bg_color => 'DDD9C4',
                                              :border => { :color => 'ff', :style => :thin,:edges=>[:left,:right,:top] }
          style_user_allocation = sheet.styles.add_style :alignment=>{:horizontal => :center},
                                              :sz=>10,
                                              :bg_color => 'EEECE1',
                                              :border => { :color => 'ff', :style => :thin },
                                              :border_top => { :color => '00', :style => :thin },
                                              :border_bottom => { :color => '00', :style => :thin }
          style_user_allocation_warn = sheet.styles.add_style :alignment=>{:horizontal => :center},
                                                         :sz=>10,:fg_color => 'FF0000',
                                                         :bg_color => 'EEECE1',
                                                         :border => { :color => 'ff', :style => :thin } ,
                                                         :border_top => { :color => '00', :style => :thin },
                                                         :border_bottom => { :color => '00', :style => :thin }
          style_issue_allocation = sheet.styles.add_style :alignment=>{:horizontal => :center},:bg_color => 'EEECE1',
                                                    :sz=>10,:border => { :color => 'ff', :style => :thin }
          style_issue_allocation_warn = sheet.styles.add_style :alignment=>{:horizontal => :center},:bg_color => 'EEECE1',
                                                          :sz=>10,:border => { :color => 'ff', :style => :thin },
                                                          :fg_color => 'FF0000'
          style_left = sheet.styles.add_style :alignment=>{:horizontal => :left},
                                              :b=>true,
                                                    :sz=>10,
                                                    :bg_color => 'DDD9C4',
                                                    :border => { :color => 'ff', :style => :thin }
          # date
          length = (@date_to-@date_from) + 1
          month_line =  ['','','','']
          date_line =  ['','','','']
          weedday_line = ['','','','']
          d = @date_from
          while d <= @date_to
            month_line << d.strftime("%b") if d.day == 1
            month_line << '' if d.day != 1
            date_line << d.day
            weedday_line << d.strftime("%a")
            d = d + 1
          end
          sheet.add_row month_line, :style=> ([nil]*4+[style_date]*length)
          sheet.add_row date_line, :style=> ([nil]*4+[style_date]*length)
          sheet.add_row weedday_line, :style=>([nil]*4+[style_week]*length), :widths=>([:auto]*4+[4]*length)
          # for each user
          data[:users].each  do |user|
            # add user line
            user_line = ["#{user[:name]}", '','','']
            user_line_style = [style_left]*4
            if user[:allocation]
              user_line = user_line + user[:allocation]
              user[:allocation].each_index do |i|
                weekday = (@date_from + i).wday
                if (user[:allocation][i] <= 8 && weekday > 0 && weekday < 6) || user[:allocation][i] == 0
                  user_line_style << style_user_allocation
                else
                  user_line_style << style_user_allocation_warn
                end
              end
            else
              user_line = user_line + ['']*length
            end
            sheet.add_row user_line,:style=>user_line_style , :widths=>([:auto]*4+[4]*length)
            # add issue
            parent_issue_stack = []
            user[:issues].each do |issue|

              # issue stack -- for indent calculation
              if(issue.id != issue.parent_id)  # is not leaf
                while parent_issue_stack[parent_issue_stack.length-1] != issue.parent_id
                  parent_issue_stack.pop();
                  if parent_issue_stack.length == 0
                    break
                  end
                end
                parent_issue_stack.push(issue.id);
              else    # is leaf
                parent_issue_stack = new Array();
                parent_issue_stack.push(issue.id);
              end
              #issue line
              issue_line = ['',">"*parent_issue_stack.length<<issue.subject, issue.project_name, "#{issue.estimated_hours} h"]
              issue_line = issue_line + [''] * (issue.start_date - @date_from) if issue.start_date > @date_from
              line_styles = [style_left]*4
              line_styles = line_styles + [nil] * (issue.start_date - @date_from) if issue.start_date > @date_from
              user[:task_allocation_of_issues][issue.id].each do |a|
                if a.work_date >= @date_from && a.work_date <= @date_to
                  issue_line << a.work_hour
                  weekday = a.work_date.wday
                  if (a.work_hour <= 8 && weekday > 0 && weekday < 6) || a.work_hour == 0
                    line_styles << style_issue_allocation
                  else
                    line_styles << style_issue_allocation_warn
                  end
                end
              end
              if !user[:task_allocation_of_issues][issue.id] ||user[:task_allocation_of_issues][issue.id].length == 0
                line_styles = line_styles + [style_issue_allocation] * (issue.due_date - issue.start_date  + 1)
                issue_line = issue_line + [''] * (issue.due_date - issue.start_date + 1)
              end
              sheet.add_row issue_line ,:style=>line_styles, :widths=>([:auto]*4+[4]*length)
            end
          end
         end
        outstrio = StringIO.new
        p.use_shared_strings = true # Otherwise strings don't display in iWork Numbers
        outstrio.write(p.to_stream.read)
        outstrio.string
      end

      private

      def coordinates(start_date, end_date, progress, zoom=nil)
        zoom ||= @zoom
        coords = {}
        if start_date && end_date && start_date < self.date_to && end_date > self.date_from
          if start_date > self.date_from
            coords[:start] = start_date - self.date_from
            coords[:bar_start] = start_date - self.date_from
          else
            coords[:bar_start] = 0
          end
          if end_date < self.date_to
            coords[:end] = end_date - self.date_from
            coords[:bar_end] = end_date - self.date_from + 1
          else
            coords[:bar_end] = self.date_to - self.date_from + 1
          end
          if progress
            progress_date = start_date + (end_date - start_date + 1) * (progress / 100.0)
            if progress_date > self.date_from && progress_date > start_date
              if progress_date < self.date_to
                coords[:bar_progress_end] = progress_date - self.date_from
              else
                coords[:bar_progress_end] = self.date_to - self.date_from + 1
              end
            end
            if progress_date < Date.today
              late_date = [Date.today, end_date].min
              if late_date > self.date_from && late_date > start_date
                if late_date < self.date_to
                  coords[:bar_late_end] = late_date - self.date_from + 1
                else
                  coords[:bar_late_end] = self.date_to - self.date_from + 1
                end
              end
            end
          end
        end
        # Transforms dates into pixels witdh
        coords.keys.each do |key|
          coords[key] = (coords[key] * zoom).floor
        end
        coords
      end

      # Sorts a collection of issues by start_date, due_date, id for gantt rendering
      def sort_issues!(issues)
        issues.sort! { |a, b| gantt_issue_compare(a, b) }
      end

      # TODO: top level issues should be sorted by start date
      def gantt_issue_compare(x, y)
        if x.root_id == y.root_id
          x.lft <=> y.lft
        else
          x.root_id <=> y.root_id
        end
      end

      def current_limit
        if @max_rows
          @max_rows - @number_of_rows
        else
          nil
        end
      end

      def abort?
        if @max_rows && @number_of_rows >= @max_rows
          @truncated = true
        end
      end

      def pdf_new_page?(options)
        if options[:top] > 180
          options[:pdf].Line(15, options[:top], PDF::TotalWidth, options[:top])
          options[:pdf].AddPage("L")
          options[:top] = 15
          options[:pdf].Line(15, options[:top] - 0.1, PDF::TotalWidth, options[:top] - 0.1)
        end
      end

      def html_subject(params, subject, options={})
        style = "position: absolute;top:#{params[:top]}px;left:#{params[:indent]}px;"
        style << "width:#{params[:subject_width] - params[:indent]}px;" if params[:subject_width]
        output = view.content_tag('div', subject,
                                  :class => options[:css], :style => style,
                                  :title => options[:title])
        @subjects << output
        output
      end

      def pdf_subject(params, subject, options={})
        params[:pdf].SetY(params[:top])
        params[:pdf].SetX(15)
        char_limit = PDF::MaxCharactorsForSubject - params[:indent]
        params[:pdf].RDMCell(params[:subject_width] - 15, 5,
                             (" " * params[:indent]) +
                                 subject.to_s.sub(/^(.{#{char_limit}}[^\s]*\s).*$/, '\1 (...)'),
                             "LR")
        params[:pdf].SetY(params[:top])
        params[:pdf].SetX(params[:subject_width])
        params[:pdf].RDMCell(params[:g_width], 5, "", "LR")
      end

      def image_subject(params, subject, options={})
        params[:image].fill('black')
        params[:image].stroke('transparent')
        params[:image].stroke_width(1)
        params[:image].text(params[:indent], params[:top] + 2, subject)
      end

      # alice
      def html_user_back(params, coords, options={})
        output = ''
        # draw line
        if coords[:bar_start] && coords[:bar_end]
          width = coords[:bar_end] - coords[:bar_start]
          style = ""
          style << "top:#{params[:top]}px;"
          style << "left:#{coords[:bar_start]}px;"
          style << "width:#{width}px;"
          output << view.content_tag(:div, '&nbsp;'.html_safe,
                                     :style => style,
                                     :class => "#{options[:css]}")
        end
        @lines << output
        output
      end

      def html_user_allocation(params, coords, options={})
        output = ''
        # draw number
        if coords[:bar_start] && coords[:bar_end] && options[:hour]
          font_color = 'warn' if ( options[:hour] > 8 || (options[:hour] > 0 && (options[:date].wday == 6 || options[:date].wday == 0)))
          s = view.content_tag(:span,
                               format("%.4g",options[:hour]),
                                :class => "#{options[:css]} #{font_color}")

          style = ""
          style << "position: absolute;"
          style << "top:#{params[:top]}px;"
          style << "left:#{coords[:bar_start]}px;"
          style << "width:#{coords[:bar_end] - coords[:bar_start]}px;"
          style << 'font-weight: bold;'
          style << "height:12px;"
          output << view.content_tag(:div, s.html_safe,
                                     :class => "task",
                                    :style => style)
        end
        @lines << output
        output
      end

      def html_task(params, coords, options={})
        output = ''
        # Renders the task bar, with progress and late
        if coords[:bar_start] && coords[:bar_end]
          width = coords[:bar_end] - coords[:bar_start] - 2
          style = ""
          style << "top:#{params[:top]}px;"
          style << "left:#{coords[:bar_start]}px;"
          style << "width:#{width}px;"
          output << view.content_tag(:div, '&nbsp;'.html_safe,
                                     :style => style,
                                     :class => "#{options[:css]} resource_task_todo")
          if coords[:bar_late_end]
            width = coords[:bar_late_end] - coords[:bar_progress_end] - 2  if coords[:bar_progress_end]
            width = coords[:bar_late_end] - coords[:bar_start] - 2  if !coords[:bar_progress_end]
            style = ""
            style << "top:#{params[:top]}px;"
            style << "left:#{coords[:bar_progress_end]}px;" if coords[:bar_progress_end]
            style << "left:#{coords[:bar_start]}px;" if !coords[:bar_progress_end]
            style << "width:#{width}px;"
            output << view.content_tag(:div, '&nbsp;'.html_safe,
                                       :style => style,
                                       :class => "#{options[:css]} resource_task_late")
          end
          if coords[:bar_progress_end]
            width = coords[:bar_progress_end] - coords[:bar_start] - 2
            style = ""
            style << "top:#{params[:top]}px;"
            style << "left:#{coords[:bar_start]}px;"
            style << "width:#{width}px;"
            output << view.content_tag(:div, '&nbsp;'.html_safe,
                                       :style => style,
                                       :class => "#{options[:css]} resource_task_done")
          end
        end
        # Renders the markers
        if options[:markers]
          if coords[:start]
            style = ""
            style << "top:#{params[:top]}px;"
            style << "left:#{coords[:start]}px;"
            style << "width:15px;"
            output << view.content_tag(:div, '&nbsp;'.html_safe,
                                       :style => style,
                                       :class => "#{options[:css]} marker starting")
          end
          if coords[:end]
            style = ""
            style << "top:#{params[:top]}px;"
            style << "left:#{coords[:end] + params[:zoom]}px;"
            style << "width:15px;"
            output << view.content_tag(:div, '&nbsp;'.html_safe,
                                       :style => style,
                                       :class => "#{options[:css]} marker ending")
          end
        end
        # Renders the label on the right
        #if options[:label]
        #  style = ""
        #  style << "top:#{params[:top]}px;"
        #  style << "left:#{(coords[:bar_end] || 0) + 8}px;"
        #  style << "width:15px;"
        #  output << view.content_tag(:div, options[:label],
        #                             :style => style,
        #                             :class => "#{options[:css]} label")
        #end
        # Renders the tooltip
        if options[:issue] && coords[:bar_start] && coords[:bar_end]
          #s = view.content_tag(:span,
          #                     view.render_issue_tooltip(options[:issue]).html_safe,
          #                     :class => "tip")
          #style = ""
          #style << "position: absolute;"
          #style << "top:#{params[:top]}px;"
          #style << "left:#{coords[:bar_start]}px;"
          #style << "width:#{coords[:bar_end] - coords[:bar_start]}px;"
          #style << "height:12px;"
          #output << view.content_tag(:div, s.html_safe,
          #                           :style => style,
          #                           :class => "tooltip")
        end
        #alice: Rander the task allocation
        if options[:issue] && coords[:bar_start] && coords[:bar_end] && options[:allocation]
          tooltip_span = view.content_tag(:span,
                                           view.render_issue_tooltip(options[:issue]).html_safe,
                                           :class => "tip")

          style = ""
          s = ""
          if options[:allocation].length > 0
            style << "width:#{(coords[:bar_end] - coords[:bar_start])/options[:allocation].length}px;"
            style << "height:12px;"

            for t in options[:allocation]
              s << view.content_tag(:span,
                                   format("%.4g",t.work_hour),
                                   :style => style,
                                   :class => "resource_task_allocation editable",
                                   :id =>  t.id)
            end
          end

          style = ""
          style << "position: absolute;"
          style << "top:#{params[:top]}px;"
          style << "left:#{coords[:bar_start]}px;"
          style << "width:#{coords[:bar_end] - coords[:bar_start]}px;"
          style << "height:12px;"
          output << view.content_tag(:div, s.html_safe+tooltip_span.html_safe,
                                     :style => style,
                                     :class => "resource_task_hide tooltip",
                                      :id => options[:issue].id)
        end

        @lines << output
        output
      end

      def pdf_task(params, coords, options={})
        height = options[:height] || 2
        # Renders the task bar, with progress and late
        if coords[:bar_start] && coords[:bar_end]
          params[:pdf].SetY(params[:top] + 1.5)
          params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
          params[:pdf].SetFillColor(200, 200, 200)
          params[:pdf].RDMCell(coords[:bar_end] - coords[:bar_start], height, "", 0, 0, "", 1)
          if coords[:bar_late_end]
            params[:pdf].SetY(params[:top] + 1.5)
            params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
            params[:pdf].SetFillColor(255, 100, 100)
            params[:pdf].RDMCell(coords[:bar_late_end] - coords[:bar_start], height, "", 0, 0, "", 1)
          end
          if coords[:bar_progress_end]
            params[:pdf].SetY(params[:top] + 1.5)
            params[:pdf].SetX(params[:subject_width] + coords[:bar_start])
            params[:pdf].SetFillColor(90, 200, 90)
            params[:pdf].RDMCell(coords[:bar_progress_end] - coords[:bar_start], height, "", 0, 0, "", 1)
          end
        end
        # Renders the markers
        if options[:markers]
          if coords[:start]
            params[:pdf].SetY(params[:top] + 1)
            params[:pdf].SetX(params[:subject_width] + coords[:start] - 1)
            params[:pdf].SetFillColor(50, 50, 200)
            params[:pdf].RDMCell(2, 2, "", 0, 0, "", 1)
          end
          if coords[:end]
            params[:pdf].SetY(params[:top] + 1)
            params[:pdf].SetX(params[:subject_width] + coords[:end] - 1)
            params[:pdf].SetFillColor(50, 50, 200)
            params[:pdf].RDMCell(2, 2, "", 0, 0, "", 1)
          end
        end
        # Renders the label on the right
        if options[:label]
          params[:pdf].SetX(params[:subject_width] + (coords[:bar_end] || 0) + 5)
          params[:pdf].RDMCell(30, 2, options[:label])
        end
      end

      def image_task(params, coords, options={})
        height = options[:height] || 6
        # Renders the task bar, with progress and late
        if coords[:bar_start] && coords[:bar_end]
          params[:image].fill('#aaa')
          params[:image].rectangle(params[:subject_width] + coords[:bar_start],
                                   params[:top],
                                   params[:subject_width] + coords[:bar_end],
                                   params[:top] - height)
          if coords[:bar_late_end]
            params[:image].fill('#f66')
            params[:image].rectangle(params[:subject_width] + coords[:bar_start],
                                     params[:top],
                                     params[:subject_width] + coords[:bar_late_end],
                                     params[:top] - height)
          end
          if coords[:bar_progress_end]
            params[:image].fill('#00c600')
            params[:image].rectangle(params[:subject_width] + coords[:bar_start],
                                     params[:top],
                                     params[:subject_width] + coords[:bar_progress_end],
                                     params[:top] - height)
          end
        end
        # Renders the markers
        if options[:markers]
          if coords[:start]
            x = params[:subject_width] + coords[:start]
            y = params[:top] - height / 2
            params[:image].fill('blue')
            params[:image].polygon(x - 4, y, x, y - 4, x + 4, y, x, y + 4)
          end
          if coords[:end]
            x = params[:subject_width] + coords[:end] + params[:zoom]
            y = params[:top] - height / 2
            params[:image].fill('blue')
            params[:image].polygon(x - 4, y, x, y - 4, x + 4, y, x, y + 4)
          end
        end
        # Renders the label on the right
        if options[:label]
          params[:image].fill('black')
          params[:image].text(params[:subject_width] + (coords[:bar_end] || 0) + 5,
                              params[:top] + 1,
                              options[:label])
        end
      end
    end
end
