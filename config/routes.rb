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
  post "batch_annotation", to: "annotation#batch_annotation"
  get  'annotation_result/:filename', to: 'annotation#annotation_result', as: 'annotation_result'

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

  end

  resources :jobs, only: [:index, :show, :destroy]
  delete 'jobs', to: "jobs#destroy_all"

  root :to => 'home#index'
end
