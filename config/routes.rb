Rails.application.routes.draw do

  require 'sidekiq/web'
  devise_scope :user do
    authenticate :user, ->(user) {user.admin} do
      mount Sidekiq::Web => '/sidekiq'
    end
  end

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get "home/about", as: "about"

  get  "find_ids_api", to: "lookup#find_ids_api"
  get  "find_ids", to: "lookup#find_ids"
  post "find_ids", to: "lookup#find_ids"
  get  "find_terms", to: "lookup#find_terms"
  get  "prefix_completion", to: "lookup#prefix_completion"
  get  "substring_completion", to: "lookup#substring_completion"
  get  "mixed_completion", to: "lookup#mixed_completion"

  get  "text_annotation", to: "annotation#text_annotation"
  post "text_annotation", to: "annotation#text_annotation"
  post "annotation_request", to: "annotation#annotation_request"
  post "annotation_tasks", to: "annotation#annotation_task"
  get "annotation_tasks/:id", to: "jobs#show", as: "annotation_task_show"

  get  'annotation_results/:filename', to: 'annotation#annotation_result', as: 'annotation_result'

  devise_for :users, controllers: {
    :omniauth_callbacks => 'callbacks',
    :confirmations => 'confirmations'
  }
  get '/users/:name' => 'users#show', :as => 'show_user'

  resources :dictionaries do
    # Add routes for a collection route, /dictionaries/...
    collection do
      get :autocomplete_user_username
    end

    # Add routes as a member, /dictionary/:id/...
    member do
      get  'show_patterns'
      get  'find_ids', to: "lookup#find_ids"
      post 'find_ids', to: "lookup#find_ids"
      get  'find_terms', to: "lookup#find_terms"
      get  'text_annotation', to: 'annotation#text_annotation'
      post 'text_annotation', to: 'annotation#text_annotation'
      get  'prefix_completion', to: 'lookup#prefix_completion'
      get  'substring_completion', to: 'lookup#substring_completion'
      get  'mixed_completion', to: 'lookup#mixed_completion'
      get 'compile'
      get 'downloadable'
      post 'downloadable', to: 'dictionaries#create_downloadable', as: 'create_downloadable'
      post 'managers', to: 'dictionaries#add_manager'
      delete 'managers/:username', to: 'dictionaries#remove_manager', as: 'manager'
    end

    resources :entries do
      collection do
        put 'empty', to: 'dictionaries#empty'
        post 'tsv', to: 'entries#upload_tsv'
        put 'switch_entries', to: 'entries#switch_to_black_entries'
        delete '/', to: 'entries#destroy_entries'
      end

      member do
        put 'undo', to: "entries#undo"
      end
    end

    resources :patterns do
      collection do
        put 'empty', to: 'dictionaries#empty'
      end

      member do
        put 'toggle'
      end
    end

    resources :jobs, only: [:show, :destroy] do
      member do
        put 'stop'
      end
    end
  end

  resources :jobs, only: [:index, :show, :destroy]
  delete 'jobs', to: "jobs#destroy_all"
  delete 'annotation_jobs', to: "jobs#destroy_all_annotation_jobs"

  root :to => 'home#index'
end
