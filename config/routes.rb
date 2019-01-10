PubDictionaries::Application.routes.draw do
  get "home/index", as: "home"
  get "home/about", as: "about"

  get  "find_ids", to: "lookup#find_ids"
  post "find_ids", to: "lookup#find_ids"
  get  "find_labels", to: "lookup#find_labels"
  post "find_labels", to: "lookup#find_labels"
  get  "prefix_completion", to: "lookup#prefix_completion"
  get  "substring_completion", to: "lookup#substring_completion"

  get  "text_annotation", to: "annotation#text_annotation"
  post "text_annotation", to: "annotation#text_annotation"
  post "annotation_request", to: "annotation#annotation_request"
  get  'annotation_result/:filename', to: 'annotation#annotation_result', as: 'annotation_result'

  # devise_for :users
  devise_for :users
  match '/users/:name' => 'users#show', :as => 'show_user'
  
  resources :dictionaries do
    post 'clone'

    # Add routes for a collection route, /dictionaries/...
    collection do
      get  'text_annotation', to: 'dictionaries#text_annotation_with_multiple_dic_readme'
      get  'select_dictionaries_for_text_annotation', to: 'dictionaries#select_dictionaries_for_text_annotation'
      post 'text_annotation', to: 'dictionaries#text_annotation_with_multiple_dic'
      get  'id_mapping', to: 'dictionaries#id_mapping_with_multiple_dic_readme'
      get  'select_dictionaries_for_id_mapping', to: 'dictionaries#select_dictionaries_for_id_mapping'
      post 'id_mapping', to: 'dictionaries#id_mapping'
      get  'label_mapping', to: 'dictionaries#label_mapping_with_multiple_dic_readme'
      get  'select_dictionaries_for_label_mapping', to: 'dictionaries#select_dictionaries_for_label_mapping'
      post 'label_mapping', to: 'dictionaries#label_mapping'
      get  'get_delayed_job_diclist'
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
      get 'test'
      get 'compile'
    end

    resources :entries do
      collection do
        put 'empty', to: 'dictionaries#empty'
      end

      member do
        put 'undo', to: "entries#undo"
      end
    end
  end

  resources :dictionaries do
    resources :jobs do
      member do
        get 'messages' => 'messages#index'
      end
    end
  end
 
  root :to => 'home#index'
end
