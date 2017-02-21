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
    # post 'entries', to: 'entries#create'
    post 'clone'

    # Add routes for a collection route, /dictionaries/...
    collection do
      #   get 'multiple_new'
      #   post 'multiple_create'
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
    end  

    # Add routes as a member, /dictionary/:id/...
    member do
      # post 'remove_entries'
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
 
  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => 'dictionaries#index', as: 'dictionaries'  --> it causes "/dictionaries#create" triggers "/create"
  root :to => 'home#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
