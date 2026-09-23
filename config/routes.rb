Rails.application.routes.draw do
  root "dashboard#index"
  resources :department_reports, only: :index

  resource :setup, only: %i[new create], controller: "setup"
  resource :session, only: %i[new create destroy]

  resources :projects, except: :destroy do
    get :ledger, on: :member
    resources :assets, except: %i[index destroy]
    resources :claims, only: %i[new create]
    resources :intake_items, except: %i[index destroy] do
      get :download, on: :member
    end
    resources :project_documents, only: %i[new create show] do
      get :download, on: :member
      patch :archive, on: :member
      post :analyze, on: :member
    end
    resources :fees, except: :destroy
    resources :bid_analyses, only: %i[new create]
    resources :generated_documents, only: %i[new create]
    resources :project_memberships, only: %i[create update destroy]
    resources :workflow_tasks, only: %i[new create]
    resources :project_milestones, except: %i[index show destroy]
    resources :claim_checklists, except: %i[index show destroy]
  end
  resources :claims, only: %i[show edit update] do
    post :resubmit, on: :member
    post :review, on: :member
    post :ai_suggest, on: :member, to: "ai_runs#create", defaults: { task_type: "claim_analysis" }
    resources :claim_materials, only: :update
  end
  resources :audit_events, only: :index
  resources :library_entries, except: :destroy do
    get :download, on: :member
  end
  resources :tender_templates, except: :destroy
  resources :tender_sources, except: %i[show destroy] do
    post :sync, on: :member
  end
  resources :tender_notices, only: %i[index show new create edit update]
  resources :bid_analyses, only: %i[show edit update] do
    resources :bid_evidences, only: :create
    resources :bid_scores, only: %i[new create edit update]
    resources :bid_simulations, only: %i[new create]
    post :review, on: :member
    post :ai_suggest, on: :member, to: "ai_runs#create", defaults: { task_type: "bid_analysis" }
  end
  resources :generated_documents, only: %i[show edit update] do
    post :ai_suggest, on: :member, to: "ai_runs#create", defaults: { task_type: "draft_document" }
    get :download_docx, on: :member
    post :submit, on: :member
    post :approve, on: :member
    post :reject, on: :member
  end
  resources :ai_runs, only: :show do
    post :approve, on: :member
    post :reject, on: :member
  end
  resources :bid_simulations, only: :show do
    post :ai_suggest, on: :member, to: "ai_runs#create", defaults: { task_type: "bid_simulation" }
  end
  resources :users, except: :destroy
  resources :roles, except: %i[show destroy]
  resources :departments, except: %i[show destroy]
  resources :workflow_tasks, only: %i[index show] do
    post :decide, on: :member
    post :restart, on: :member
  end
  resources :notifications, only: %i[index update]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
