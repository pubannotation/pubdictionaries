Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get "home/about", as: "about"

  get  "find_ids", to: "lookup#find_ids"
  post "find_ids", to: "lookup#find_ids"
  get  "prefix_completion", to: "lookup#prefix_completion"
  get  "substring_completion", to: "lookup#substring_completion"

  get  "text_annotation", to: "annotation#text_annotation"
  post "text_annotation", to: "annotation#text_annotation"
  post "annotation_request", to: "annotation#annotation_request"
  post "annotation_job", to: "annotation#annotation_job"
  post "annotation_tasks", to: "annotation#annotation_task"
  get "annotation_tasks/:id", to: "jobs#show", as: "annotation_task_show"

  get  'annotation_results/:filename', to: 'annotation#annotation_result', as: 'annotation_result'

  devise_for :users
  get '/users/:name' => 'users#show', :as => 'show_user'

  resources :dictionaries do
    # Add routes for a collection route, /dictionaries/...
    collection do
      get :autocomplete_user_username
    end

    # Add routes as a member, /dictionary/:id/...
    member do
      get  'find_ids', to: "lookup#find_ids"
      post 'find_ids', to: "lookup#find_ids"
      get  'text_annotation', to: 'annotation#text_annotation'
      post 'text_annotation', to: 'annotation#text_annotation'
      get  'prefix_completion', to: 'lookup#prefix_completion'
      get  'substring_completion', to: 'lookup#substring_completion'
      get 'compile'
      post 'managers', to: 'dictionaries#add_manager'
      delete 'managers/:username', to: 'dictionaries#remove_manager', as: 'manager'
    end

    resources :entries do
      collection do
        put 'empty', to: 'dictionaries#empty'
        post 'tsv', to: 'entries#upload_tsv'
      end

      member do
        put 'undo', to: "entries#undo"
      end
    end

    resources :jobs, only: [:show, :destroy]
  end

  resources :jobs, only: [:index, :show, :destroy]
  delete 'jobs', to: "jobs#destroy_all"

  root :to => 'home#index'
end
