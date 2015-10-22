PubDictionaries::Application.routes.draw do

  resources :mapping do
    collection do
      get  "term_to_id"
      post "term_to_id", to: "mapping#term_to_id_post"
      # get "term_to_id", to: "mapping#term_to_id_post"

      get  "id_to_label"
      post "id_to_label", to: "mapping#id_to_label_post"

      get  "text_annotation"
      post "text_annotation", to: "mapping#text_annotation_post"

      get  'select_dictionaries', to: 'mapping#select_dictionaries'

      get "search"
      get "expression_to_id"
      post "expression_to_id"
      get "id_to_expression"
      post "id_to_expression"
      get :autocomplete_expression_name 
    end
  end

  # devise_for :users
  devise_for :users
  
  get "welcome/index"

  get "about/index"

  get "manual/basic"
  get "manual/advanced"
  get "manual/pubann"
  
  get "web_services/index"
  get "web_services/annotation_with_single_dic"
  get "web_services/annotation_with_multiple_dic"
  get "web_services/ids_to_labels"
  get "web_services/terms_to_idlists"

  resources :users do
    resources :dictionaries
    resources :user_dictionaries
  end

  resources :dictionaries do
    resources :entries

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
      post 'disable_entries'
      post 'remove_entries'
      get  'text_annotation', to: 'dictionaries#text_annotation_with_single_dic_readme'
      post 'text_annotation', to: 'dictionaries#text_annotation_with_single_dic'
      get 'test'
    end
  end

  resources :user_dictionaries do
    resources :new_entries
    resources :removed_entries

    collection do
      get 'index_for_owner'
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
  # root :to => 'welcome#index'
  # root :to => 'dictionaries#index', as: 'dictionaries'  --> it causes "/dictionaries#create" triggers "/create"
  root :to => 'welcome#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
