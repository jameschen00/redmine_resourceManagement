# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

get 'user_allocation_gantt', :to => 'user_allocation_gantt#show2'
get 'user_allocation_gantt_xls', :to => 'user_allocation_gantt#user_allocation_gantt_xls'
#get 'test', :to => 'user_allocation_gantt#show'
get 'resourcemng_data.json', :to => 'user_allocation_gantt#search'
post 'ajax_update_task_allocation', :to => 'user_allocation_gantt#update_task_allocation'
get 'ajax_update_task', :to => 'user_allocation_gantt#update_task'

get 'project_status', :to => 'project_status#index'