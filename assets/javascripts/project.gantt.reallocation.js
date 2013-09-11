
(function ( $ ) {
    var current_editing_div; //current div being edited by user
    var chart_json;
    var settings;
    var right_width;
    var content_height;
    var date_from;
    var date_to;
    /**
     * main entry
     * @param options
     * @returns {*}
     */
    $.fn.jsrm = function(options) {
        // merge settings
        settings = $.extend({}, $.fn.jsrm.defaults,options );

        return this.each(function(){
            var container = this;
            $.ajax({
                type: 'GET',
                url: settings.data,
                success: function(chart,textStatus,jqXHR){
                    chart_json = chart;
                    date_from = parseDate(chart_json.date_from);
                    date_to = parseDate(chart_json.date_to);
                    settings.onDataReceived.call(textStatus) ;
                    var max_line = maxLine(settings,chart_json);
                    var table = createTable(settings, container, max_line,chart_json);
                    draw(settings,chart_json,table);
                    addDraggable();
                    addResizable();
                    $('.jsrm_task').dblclick(showForm);
                }
            });
        });
    };
    /**
     * default options.
     * @type {{subject_width: number, line_height: number, data: string, editable: boolean, date_column_width: number, indent: number, line_gap: number, onDataReceived: Function}}
     */
    $.fn.jsrm.defaults = {
        subject_width: 400,       // width of left area
        line_height: 17,          // title line and content line
        data: '',                  // get url, return json
        editable:false,           // if allocation is editable
        date_column_width:30,    // width of each day in right area
        indent:15,                 // indent for issues under someone
        line_gap:15,
        onDataReceived: function(){} //function of how to show data on the chart
    };

    function addResizable(){
//        $(".jsrm_leaf").resizable({
//            grid:[settings.date_column_width, 0],
//            minWidth:settings.date_column_width,
//            handles:"e,w",
//            resize: function(){
//                var width = $(this).width();
//                var new_num = Math.round(width/settings.date_column_width);
//                var old_num = $(this).children("span").length;
//                if(old_num > new_num){
//                    var diff = old_num-new_num;
//                    for(var i= 0;i<diff;i++){
//                        $($(this).children("span")[0]).remove();
//                    }
//                }
//                $(this).css('width',$(this).css('width'));
//                var scroll = $(this).parent().scrollLeft() || 0;
//                $(this).css('left',parseInt($(this).css('left'))+scroll);
//                if(parseInt($(this).css('left')) < -1){
//                    $(this).css('left',-1);
//                }
//                if(parseInt($(this).css('left')) > right_width){
//                    $(this).css('width',right_width);
//                }
//            },
//            stop:function(){
//                var start = dateAdd(date_from,  Math.round(parseInt($(this).css('left'))/settings.date_column_width));
//                var end = dateAdd(start,Math.round($(this).width()/settings.date_column_width)-1);
//                var issue_id = $(this).attr('issue_id');
//                var div = $(this);
//                $.ajax({
//                    type: 'GET',
//                    url: 'ajax_update_task' ,
//                    data: 'start='+dateToString(start)+'&end='+dateToString(end)+"&issue_id="+issue_id,
//                    success: function(json){
//                        if(json.allocation && json.issue){
//                            updateRightIssue(div,json.allocation,json.issue.issue);
//                            updateRightTotalAllocationDetail(chart_json,json);
//                        }else{
//                            alertError();
//                        }
//                    }   ,
//                    error: function(){
//                        alertError();
//                    }
//                });
//            }
//        })  ;
    }

    function addDraggable(){
//        $(".jsrm_leaf").draggable({
//            axis: "x" ,
//            cursor: "move",
//            grid:[settings.date_column_width, 0],
//            drag: function(event, ui){
//            },
//            stop: function(){
//                if(right_width < (parseInt($(this).css('left')) + $(this).width()) - 1){
//                    $(this).css('left', right_width - $(this).width() + 1);
//                }
//                if(parseInt($(this).css('left')) < -1){
//                    $(this).css('left', -1);
//                }
//                $( this ).draggable( "option", "revert", false );
//                //if disabled (revert is true)
//                if($( ".jsrm_leaf" ).draggable( "option", "revert" )){
//                    return;
//                }
//
//                var start = dateAdd(date_from,  Math.round(parseInt($(this).css('left'))/settings.date_column_width));
//                var end = dateAdd(start,Math.round($(this).width()/settings.date_column_width)-1);
//                var issue_id = $(this).attr('issue_id');
//                var div = $(this);
//                $.ajax({
//                    type: 'GET',
//                    url: 'ajax_update_task' ,
//                    data: 'start='+dateToString(start)+'&end='+dateToString(end)+"&issue_id="+issue_id,
//                    success: function(json){
//                        if(json.allocation && json.issue){
//                            updateRightIssue(div,json.allocation,json.issue.issue);
//                            updateRightTotalAllocationDetail(chart_json,json);
//                        }else{
//                            alertError();
//                        }
//                    }   ,
//                    error: function(){
//                        alertError();
//                    }
//                });
//            }
//        });
    }


    function alertError(){
        alert('Fail! Please refresh the page and try again.');
        window.location.reload();
    }

    /**
     * calculate total number of lines
     * @param settings
     * @param data
     * @returns {number}
     */
    function maxLine(settings,data){
        var line = 0;
        var users = data.users;
        for(var i = 0; i < users.length; i++){
            var user = users[i];
            var issues = user.issues;
            line += 1 + issues.length;
        }
        return line;
    }

    /**
     * show data on chart
     * @param settings
     * @param data
     * @param table
     */
    function draw(settings,data,table){
        var users = data.users;
        var left_container = $(".jsrm_left_div");
        var right_container = $(".jsrm_right_div")
        var top = settings.line_height * 2 + settings.line_gap;
        //for each user
        for(var i = 0; i < users.length; i++){
            var user = users[i];
            var issues = user.issues;
            var left = 4;

            //left subject of user
            var div = drawLeftUser(settings, top, left, user);
            left_container.append(div);

            //right total allocation of user
            div = drawRightTotalAllocation(settings, user, top,calculateRightWidth(settings,data));
            right_container.append(div);

            // line ++
            top += settings.line_height + settings.line_gap;

            // for each issue
            var parent_issue_stack = new Array();
            for(var j = 0; j < issues.length; j++){
                var issue = issues[j].issue;

                //issue stack -- for indent calculation
                if(issue.id != issue.parent_id){   // is not leaf
                    while(parent_issue_stack[parent_issue_stack.length-1] != issue.parent_id){
                        parent_issue_stack.pop();
                        if(parent_issue_stack.length == 0){break;}
                    }
                    parent_issue_stack.push(issue.id);
                }else{    // is leaf
                    parent_issue_stack = new Array();
                    parent_issue_stack.push(issue.id);
                }
                left = 4 + settings.indent * parent_issue_stack.length;

                //left subject of issue
                div = drawLeftIssue(settings,issue,top,left);
                left_container.append(div);
//                div = drawLeftDays(settings,issue,top,left);
//                left_container.append(div);

                //right date of issue
                if(issue.start_date && issue.due_date && issue.estimated_hours){
                    div = drawRightIssue(settings,user.task_allocation_of_issues, issue,top);
                    right_container.append(div);
                }

                //line ++
                top += settings.line_height + settings.line_gap;
            }
        }
        table.css('height',settings.line_height*2+top+settings.line_gap);
    }

    function drawLeftUser(settings, top, left, user){
        var div = $("<div class='jsrm_line jsrm_left_title'/>");
        div.css('top',top);
        div.css('left',left);
        div.css('width',settings.subject_width - left -2);
        div.css('height',settings.line_height);
        var span = ($("<span class='icon icon-projects '  style='width:50%'> </span>"));
        if(user.url || user.url.length == 0){
            span.append($("<a href='"+user.url+"'>"+user.name+"</a>")) ;
        }else{
            span.text(user.name);
        }
        div.append(span);

        return div;
    }

    function drawRightTotalAllocation(settings,user,top,width){
        var total_allocation = user.allocation;
        //background
        var div = $("<div class='jsrm_personal_allocation_back' />");
        div.css('height',settings.line_height);
        div.css('top',top);
        div.css('width',width);
        div.attr('user_id',user.id);
        //detail
        var k = 0;
        var date = date_from;
        while(date - date_to <= 0){
            var span = $("<span/>");
            span.css('width', settings.date_column_width);
            span.attr('class','jsrm_total_allocation');
            div.append(span);
            date = nextDate(date);
            k++;
        }
        drawRightTotalAllocationDetail(div,user);
        return div;
    }
    function drawRightTotalAllocationDetail(div,user){
        var span_list = div.children("span");
        var allocation_of_issues = user.task_allocation_of_issues;
        $.each(allocation_of_issues,function(issue_id, allocation_of_issue){
            $.each(allocation_of_issue,function(i,allocation){
                allocation = allocation.task_allocation;
                var work_date = parseDate(allocation.work_date);
                var span_index = dateDiff(date_from,work_date);
                var val = parseFloat($(span_list[span_index]).text()) || 0;
                val = val + parseFloat(allocation.work_hour);
                $(span_list[span_index]).text(val);
                if(val > 8 || ((work_date.getDay() == 0 || work_date.getDay() == 6) && val > 0)){
                    $(span_list[span_index]).addClass('warn');
                }
            });
        });
    }
    function updateRightTotalAllocationDetail(data,json){
        var assigned_to = json.issue.issue.assigned_to_id || 0;
        var user_div = $("div[user_id='"+assigned_to+"']");
        var new_issue_allocation = json.allocation;
        $.each(data.users, function(i,user){

            if(user.id == (assigned_to).toString()){
                //new json segment replace chart_json
                user.task_allocation_of_issues[json.issue.issue.id] = json.allocation;
                //
                var date = date_from;
                var span_list = user_div.children("span");
                var i = 0;
                // for each span clear text
                $.each(span_list,function(i,span){
                    $(span).attr('class','jsrm_total_allocation');
                    $(span).text('');
                });
                //draw
                drawRightTotalAllocationDetail(user_div,user);
                return;
            }
        });
    }
    function  drawLeftIssue(settings,issue,top,left){
        var div = $("<div class='issue-subject jsrm_line jsrm_left_title'/>");
        div.css('top',top);
        div.css('left',left);
        div.css('width',settings.subject_width - left);
        div.css('height',settings.line_height);
        var w = div.width();
        //hours
        var hour = issue.estimated_hours || 0;
        var span2 = ($("<span style='text-align: right;display: inline-block;' />"));
        span2.text("("+hour+"h)")  ;
        span2.css('width',50);
        w = w - 50;
        //issue title
        var span1 = ($("<span class='icon icon-issue'> </span>"));
        span1.css('width',w * 2 / 3 - 25);//25=icon's padding
        var a = $("<a class='issue status-1 priority-2 priority-default' href='issues/"+issue.id+"' style='width:90%;text-overflow:ellipsis; -o-text-overflow:ellipsis; overflow:hidden;'/>")
        a.text(issue.subject);
        a.attr('title',issue.subject);
        span1.append(a);
        //project title
        a = $("<a href='projects/"+issue.project_identifier+"' title='" + issue.project_name +
            "' style='display:inline-block;text-overflow:ellipsis; -o-text-overflow:ellipsis; overflow:hidden;'> "
            +issue.project_name+"</a>");
        a.css('width', w/3);

        div.append(span1);
        div.append(a);
        div.append(span2);
        return div;
    }

    function updateRightIssue(div,allocation,issue){
        var days = dateDiff(parseDate(issue.start_date),nextDate(parseDate(issue.due_date)));
        var width = days * settings.date_column_width;
        var right_left = dateDiff(date_from, parseDate(issue.start_date)) * settings.date_column_width;
        // remove old allocation
        div.children('span').remove();
        //set new left & width
        div.css('left',right_left - 1);
        if(parseDate(issue.due_date) > date_to){
            div.css('width',dateDiff(parseDate(issue.start_date), nextDate(date_to)) * settings.date_column_width );
        }else{
            div.css('width',width );
        }
        //draw detail
        for(var m = 0; (m < allocation.length && parseDate(allocation[m].task_allocation.work_date)<=date_to); m++){
            var span = drawRightIssueDetail(settings,allocation,m);
            div.append(span);
        }
    }

    function drawRightIssue(settings,task_allocation,issue,top){
        var allocation = task_allocation[issue.id];
        var days = dateDiff(parseDate(issue.start_date),nextDate(parseDate(issue.due_date)));
        var width = days * settings.date_column_width;
        var right_left = dateDiff(date_from, parseDate(issue.start_date)) * settings.date_column_width;
        //draw border,  and background
        var div = $("<div class='jsrm_task'/>");
        if(issue.id != issue.parent_id){
            div.addClass('jsrm_leaf');
        }
        div.css('top',top);
        div.css('left',right_left - 1);
        div.attr('issue_id',issue.id);
        if(parseDate(issue.due_date) > date_to){
            div.css('width',dateDiff(parseDate(issue.start_date), nextDate(date_to)) * settings.date_column_width );
        }else{
            div.css('width',width );
        }
        div.css('height',settings.line_height);
        //draw details
        for(var m = 0; (m < allocation.length && parseDate(allocation[m].task_allocation.work_date)<=date_to); m++){
            var span = drawRightIssueDetail(settings,allocation,m);
            div.append(span);
        }
        return div;
    }
    function drawRightIssueDetail(settings,allocation,index){
        var span = $("<span class='resource_task_allocation editable'/>");
        span.css('width', settings.date_column_width);
        span.text(allocation[index].task_allocation.work_hour);
        span.attr('id',allocation[index].task_allocation.id);
        return span;
    }

    /**
     *
     * @param settings
     * @param data
     * @returns {number}
     */
    function calculateRightWidth(settings,data){
        return dateDiff(parseDate(data.date_from),nextDate(parseDate(data.date_to)))*settings.date_column_width;
    }

    /**
     * create a table for chart, with left div for titles and right div for daily detail
     * @param settings
     * @param div
     * @param max_line
     * @param data
     * @returns {*|HTMLElement}
     */
    function createTable(settings, div, max_line,data){
        var table = $("<table class='jsrm_table'/>");
        var tbody = $("<tbody/>");
        var tr = $("<tr/>");

        content_height = max_line * (settings.line_height+settings.line_gap) + settings.line_gap;
        right_width = calculateRightWidth(settings,data);

        var td_left = $("<td class='jsrm_table_left' style='width:"+ settings.subject_width + "px;height:200px'/>");
        var left_div = $("<div class='jsrm_left_div' style='width:" + settings.subject_width + "px;height:"+(content_height+settings.line_height*2+24)+"px'/>");
        var left_header = $("<div class='jsrm_gantt_hdr jsrm_left_header' style='height:"  + (settings.line_height * 2) + "px;width:" + (settings.subject_width-1) + "px'/>");
        var left_border = $("<div class='jsrm_gantt_hdr jsrm_left_border' style='width:" + (settings.subject_width-2) + "px;height:"+(content_height+settings.line_height*2)+"px'/>");
        var left_gantt_subjects = $("<div class='gantt_subjects'/>");
        td_left.append(left_div);
        left_div.append(left_header);
        left_div.append(left_border);

        var td_right = $("<td/>");
        var right_div = $("<div class='jsrm_right_div' style='height:"+(content_height+settings.line_height*2+24)+"px'/>");
        var right_header = $("<div class='jsrm_gantt_hdr jsrm_right_header' style='width:"+(right_width-1)+"px;height:"+(settings.line_height * 2)+"px'/>")
        var month_div_list = createMonthDiv(settings,data);
        var date_div_list = createDateDiv(settings, content_height,data);
        td_right.append(right_div);
        right_div.append(right_header);
        for(var i = 0; i < month_div_list.length; i++){
            right_div.append(month_div_list[i]);
        }
        for(var i = 0; i < date_div_list.length; i++){
            right_div.append(date_div_list[i]);
        }

        tr.append(td_left);
        tr.append(td_right);
        tbody.append(tr);
        table.append(tbody);
        $(div).append(table);
        return table;
    }

    /**
     * draw month div
     * @param settings
     * @param data
     * @returns {Array}
     */
    function createMonthDiv(settings, data){
        var start = date_from;
        var end =   date_to;
        var divlist = [];
        var date = start;
        var left = 0;
        while(true){
            var month_end = new Date(date.getFullYear(),date.getMonth(),daysOfMonth(date));
            var div = $("<div class='jsrm_gantt_hdr'/>");
            div.css('left',left + 'px');
            div.css('height',settings.line_height+'px');
            div.text(date.getFullYear() + "-" + (date.getMonth()+1));
            if(month_end - end >= 0){
                var w = (dateDiff(date,end) + 1) * settings.date_column_width;
                div.css('width',(w-1) +"px");   //spare 1px to border
                if(w < 100){               // if there is no room for year-month, just show month
                    div.text(date.getMonth()+1);
                }
                divlist = divlist.concat([div]);
                break;
            }else{
                var w = (dateDiff(date,month_end) + 1) * settings.date_column_width ; //spare 1px to border
                div.css('width',(w-1)+"px");    //spare 1px to border
                divlist = divlist.concat([div]);
                left = left + w;
            }
            date = new Date(date.getFullYear(),date.getMonth()+1,1);
        }
        return divlist;
    }

    /**
     * draw date div
     * @param settings
     * @param content_height
     * @param data
     * @returns {Array}
     */
    function createDateDiv(settings, content_height,data){
        var start =   parseDate(data.date_from);
        var end =   parseDate(data.date_to);
        var divlist = [];
        var date = start;
        var left = 0;
        while(date - end <= 0){
            //date frame
            var div = $("<div class='jsrm_gantt_hdr'/>");
            div.css('left',left + 'px');
            div.css('height',(content_height+settings.line_height-1)+'px');
            div.css('top',(settings.line_height+1)+'px');
            div.text(date.getDate());
            div.css('width',(settings.date_column_width -1) +"px"); // spare 1px to border
            if(date.getDay() == 0 || date.getDay() == 6){
                div.addClass("jsrm_nwday");
            }
            divlist = divlist.concat([div]);
            //today line
            var today = new Date();
            if(date.getFullYear() == today.getFullYear() && date.getMonth() == today.getMonth() && date.getDate() == today.getDate()){
                var div = $("<div class='jsrm_today_line'/>");
                div.css('left',(left + 0.5 * settings.date_column_width) + 'px');
                div.css('height',(content_height+settings.line_height-1)+'px');
                div.css('top',(settings.line_height+1)+'px');
            }
            divlist = divlist.concat([div]);

            //next day
            date = nextDate(date);
            left = left + settings.date_column_width;
        }
        return divlist;
    }

    /**
     *
     * @param start     date
     * @param end       date
     * @returns {number}
     */
    function dateDiff(start,end){
        return ((end-start)/(3600*24*1000));
    }

    /**
     *
     * @param day    Date
     * @returns {number}
     */
    function daysOfMonth(day){
        var start = new Date(day.getFullYear(),day.getMonth(),1);
        var end = new Date(day.getFullYear(),day.getMonth()+1,1);
        return ((end-start)/(3600*24*1000));
    }

    /**
     *
     * @param date
     * @returns {*}
     */
    function parseDate(date){
        if(date == undefined)
            return undefined;
        return  new   Date(Date.parse(date.replace(/-/g,   "/")));
    }

    /**
     *
     * @param date
     * @returns {Date}
     */
    function nextDate(date){
        return new Date(date.getFullYear(),date.getMonth(),date.getDate()+1);
    }

    /**
     *
     * @param date
     * @param diff
     * @returns {Date}
     */
    function dateAdd(date, diff){
        return new Date(date.getFullYear(),date.getMonth(),date.getDate()+diff);
    }

    function dateToString(date){
        return date.getFullYear()+"-"+(date.getMonth()+1)+"-"+date.getDate();
    }


    /**
     * show form to edit allocation of an issue
     */
    function showForm(){
        disableDragAndResize();

        current_editing_div = $(this);
        var div = current_editing_div;
        if($(this).tagName == 'DIV'){
            div = $this;
        }else if($(this).tagName == 'SPAN'){
            div = $this.parent();
        }
        var span_list = div.children("span[class *= 'editable']");
        if(span_list.length == 0){
            enableDragAndResize();
            return;
        }

        var form = $('<form action="user_allocation_gantt.json" method="post" />');
        var text;
        for(var i = 0; i < span_list.length; i++){
            var id = $(span_list[i]).attr('id');
            var width =  $(span_list[i]).css('width');
            var fontsize = $(span_list[i]).css('font-size');
            text = $('<input type="text" />');
            text.val($(span_list[i]).text());
            text.attr('old',$(span_list[i]).text());
            text.attr('name','resource_task_allocation[allocation][]') ;
            text.attr('id',id) ;
            text.attr('class','resource_task_allocation') ;
            text.css('width',width);
            text.css('width','-=1');
            text.css('font-size',fontsize);
            form.append(text);
            form.append($("<input type='hidden' name='resource_task_allocation[id][]' value='"+id+"'/>"));
        }
        form.submit(function(){return false;});
        div.children("span").remove();
        div.append(form);
        div.removeClass("resource_task_hide");
        div.addClass("resource_task_show");
        $(div).unbind('dblclick');
        $("html").click(closeForm);
        $(div).click(stop);
        text.focus();
    }

    /**
     *
     * @param e
     */
    function stop(e){
        e.stopPropagation();
    }

    /**
     * submit form and replace form with new data
     * @param e
     * @returns {boolean}
     */
    function closeForm(e){
        var isSubmit = confirm("Are you sure to submit the new allocation.");

        var div = current_editing_div;
        current_editing_div = undefined;
        var form = div.children('form');
        var input_boxes = form.children("input[type='text']");

        //submit
        if(isSubmit){
            //save
            $.ajax({
                url:"ajax_update_task_allocation",
                type: 'POST',
                data: form.serialize(),
                success: function(json,textStatus,jqXHR){
                    if(json && json.allocation){
//                            showData(form,div,input_boxes,true);
                        //alert('OK');
                        form.remove();
                        div.children('span').remove();

                        for(var m = 0; (m < json.allocation.length); m++){
                            // if issue's start < start_date, don't draw
                            if(parseDate(json.allocation[m].task_allocation.work_date)<date_from){
                                continue;
                            }
                            // if issue's end < end_date, stop drawing
                            if(parseDate(json.allocation[m].task_allocation.work_date)>date_to){
                                break;
                            }
                            var span = drawRightIssueDetail(settings,json.allocation,m);
                            div.append(span);
                        }
                        updateRightTotalAllocationDetail(chart_json,json);
                        div.dblclick(showForm);
                        $(div).click(stop);
                    }else{
                        showData(form,div,input_boxes,false);
                        alert('Error:'+jqXHR+textStatus);
                    }
                    enableDragAndResize();
                    $("html").unbind('click',closeForm);
                },
                error: function(jqXHR,textStatus,errorThrown ){
                    showData(form,div,input_boxes,false);
                    alert('Error:'+jqXHR+textStatus);
                    enableDragAndResize();
                    $("html").unbind('click',closeForm);
                }
            });
        }else{
            showData(form,div,input_boxes,false);
            $("html").unbind('click',closeForm);
            enableDragAndResize();
        }
        return false;
    }

    /**
     * show data to replace form
     * @param form
     * @param div
     * @param input_boxes
     * @param isShowNewData
     */
    function showData(form,div,input_boxes,isShowNewData){
        // show data
        for(var i = 0; i < input_boxes.length; i++){
            var id = $(input_boxes[i]).attr('id');
            var width =  $(input_boxes[i]).css('width');
            var fontsize = $(input_boxes[i]).css('font-size');
            var span = $('<span />');
            if(isShowNewData){
                span.text($(input_boxes[i]).val());
            }else{
                span.text($(input_boxes[i]).attr('old'));
            }
            span.attr('id',id);
            span.attr('class','resource_task_allocation editable') ;
            span.css('width',width);
            span.css('width','+=1');
            span.css('font-size',fontsize);
            span.appendTo(div);
        }
        form.remove();
        div.addClass("resource_task_hide");
        div.removeClass("resource_task_show");
        div.children("div").css("display","block");
        $(div).bind('dblclick',showForm);
        $("html").unbind('click');
    }

    function enableDragAndResize(){
//        //enable drag
//        $( ".jsrm_leaf" ).draggable( "option", "revert", false );
//        $( ".jsrm_leaf" ).draggable( "option", "disabled", false );
//        //enable resize
//        $( ".jsrm_leaf" ).children("div").css('display','inline-block');
    }
    function disableDragAndResize(){
//        //enable drag
//        $( ".jsrm_leaf" ).draggable( "option", "revert", true );
//        $( ".jsrm_leaf" ).draggable( "option", "disabled", true );
//        //enable resize
//        $( ".jsrm_leaf" ).children("div").css('display','none');
    }

}( jQuery ));

