PubDictionaries::Application.routes.draw do

  # devise_for :users
  devise_for :users
  
  get "welcome/index"

  get "web_services/index"
  get "web_services/exact_string_match"
  get "web_services/exact_string_match_single_dic"
  get "web_services/approximate_string_match"
  get "web_services/approximate_string_match_single_dic"
  get "web_services/ids_to_labels"
  get "web_services/terms_to_idlists"

  get "manual/basic"
  get "manual/advanced"
  
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
      post 'text_annotation', to: 'dictionaries#text_annotation_with_multiple_dic'
      post 'ids_to_labels'
      post 'terms_to_idlists'
    end  


    # Add routes as a member, /dictionary/:id/...
    member do
      post 'disable_entries'
      post 'remove_entries'
      post 'text_annotation', to: 'dictionaries#text_annotation_with_single_dic'
    end
  end

  resources :user_dictionaries do
    resources :new_entries
    resources :removed_entries
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
