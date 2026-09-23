class CreateCoreDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :status, null: false, default: "active"
      t.datetime :last_sign_in_at
      t.timestamps
    end
    add_index :users, :public_id, unique: true
    add_index :users, :email, unique: true

    create_table :roles do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.json :permissions, null: false, default: []
      t.timestamps
    end
    add_index :roles, :code, unique: true

    create_table :user_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.timestamps
    end
    add_index :user_roles, %i[user_id role_id], unique: true

    create_table :departments do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :departments, :public_id, unique: true
    add_index :departments, :code, unique: true

    create_table :projects do |t|
      t.string :public_id, null: false
      t.string :code, null: false
      t.string :name, null: false
      t.string :project_type, null: false
      t.string :status, null: false, default: "draft"
      t.references :department, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.date :start_date
      t.date :due_date
      t.text :description
      t.json :metadata, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :projects, :public_id, unique: true
    add_index :projects, :code, unique: true
    add_index :projects, %i[project_type status]

    create_table :project_memberships do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :membership_role, null: false, default: "member"
      t.timestamps
    end
    add_index :project_memberships, %i[project_id user_id], unique: true

    create_table :intake_items do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :category, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "pending"
      t.string :custodian
      t.datetime :received_at
      t.text :note
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :intake_items, :public_id, unique: true
    add_index :intake_items, %i[project_id category status]

    create_table :project_documents do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :category, null: false
      t.string :status, null: false, default: "uploaded"
      t.string :original_filename, null: false
      t.string :content_type
      t.bigint :byte_size
      t.string :sha256
      t.string :ocr_status, null: false, default: "pending"
      t.text :ocr_text
      t.string :analysis_status, null: false, default: "pending"
      t.json :metadata, null: false, default: {}
      t.references :uploaded_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :project_documents, :public_id, unique: true
    add_index :project_documents, :sha256
    add_index :project_documents, %i[project_id category]

    create_table :assets do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :asset_code, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.string :address
      t.string :rights_no
      t.string :appraisal_org
      t.decimal :appraisal_value, precision: 18, scale: 2
      t.string :disposal_status, null: false, default: "pending"
      t.references :updated_by, null: false, foreign_key: { to_table: :users }
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :assets, :public_id, unique: true
    add_index :assets, %i[project_id asset_code], unique: true
    add_index :assets, %i[project_id rights_no]

    create_table :asset_versions do |t|
      t.references :asset, null: false, foreign_key: true
      t.references :changed_by, null: false, foreign_key: { to_table: :users }
      t.string :change_reason, null: false
      t.decimal :appraisal_value, precision: 18, scale: 2
      t.json :snapshot, null: false, default: {}
      t.timestamps
    end

    create_table :claims do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :creditor_name, null: false
      t.string :unified_code
      t.string :contact_name
      t.string :contact_phone
      t.decimal :claim_amount, null: false, precision: 18, scale: 2, default: 0
      t.string :currency, null: false, default: "CNY"
      t.string :claimed_type, null: false, default: "unknown"
      t.string :recommended_type
      t.string :status, null: false, default: "received"
      t.decimal :completeness_score, precision: 5, scale: 2
      t.string :risk_level, null: false, default: "unrated"
      t.text :summary
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :claims, :public_id, unique: true
    add_index :claims, %i[project_id status]
    add_index :claims, %i[project_id creditor_name]

    create_table :claim_materials do |t|
      t.references :claim, null: false, foreign_key: true
      t.references :project_document, foreign_key: true
      t.string :material_type, null: false
      t.boolean :present, null: false, default: false
      t.boolean :signature_detected
      t.boolean :seal_detected
      t.boolean :authorization_complete
      t.string :page_reference
      t.text :note
      t.references :checked_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :claim_materials, %i[claim_id material_type], unique: true

    create_table :claim_reviews do |t|
      t.references :claim, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.string :stage, null: false
      t.string :decision, null: false
      t.text :comment, null: false
      t.json :evidence, null: false, default: []
      t.timestamps
    end
    add_index :claim_reviews, %i[claim_id stage created_at]

    create_table :workflow_tasks do |t|
      t.string :public_id, null: false
      t.references :project, null: false, foreign_key: true
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :stage, null: false
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.datetime :due_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :workflow_tasks, :public_id, unique: true
    add_index :workflow_tasks, %i[record_type record_id]
    add_index :workflow_tasks, %i[assignee_id status]

    create_table :workflow_events do |t|
      t.references :workflow_task, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :decision, null: false
      t.text :comment, null: false
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    create_table :fees do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :fee_type, null: false
      t.decimal :receivable, precision: 18, scale: 2, null: false, default: 0
      t.decimal :received, precision: 18, scale: 2, null: false, default: 0
      t.string :invoice_status, null: false, default: "not_issued"
      t.date :received_on
      t.text :note
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :fees, :public_id, unique: true
    add_index :fees, %i[project_id fee_type]

    create_table :tender_templates do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :project_category, null: false
      t.string :tender_method, null: false
      t.text :body, null: false
      t.integer :version, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :tender_templates, :public_id, unique: true

    create_table :tender_sources do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :base_url, null: false
      t.string :access_mode, null: false, default: "public_api"
      t.boolean :authorized, null: false, default: false
      t.boolean :active, null: false, default: true
      t.json :filters, null: false, default: {}
      t.datetime :last_synced_at
      t.timestamps
    end
    add_index :tender_sources, :public_id, unique: true

    create_table :tender_notices do |t|
      t.references :tender_source, foreign_key: true
      t.string :public_id, null: false
      t.string :external_id
      t.string :title, null: false
      t.string :url, null: false
      t.string :region
      t.string :industry
      t.datetime :published_at
      t.datetime :deadline_at
      t.json :tags, null: false, default: []
      t.string :status, null: false, default: "new"
      t.timestamps
    end
    add_index :tender_notices, :public_id, unique: true
    add_index :tender_notices, %i[tender_source_id external_id], unique: true
    add_index :tender_notices, %i[status deadline_at]

    create_table :bid_analyses do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :status, null: false, default: "pending"
      t.json :criteria, null: false, default: []
      t.json :risks, null: false, default: []
      t.json :outline, null: false, default: []
      t.decimal :simulated_score, precision: 8, scale: 2
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :bid_analyses, :public_id, unique: true

    create_table :generated_documents do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :kind, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :status, null: false, default: "draft"
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.timestamps
    end
    add_index :generated_documents, :public_id, unique: true

    create_table :ai_runs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :task_type, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :provider
      t.string :model
      t.string :prompt_sha256
      t.json :evidence_refs, null: false, default: []
      t.text :output
      t.string :status, null: false, default: "queued"
      t.integer :input_tokens
      t.integer :output_tokens
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :review_note
      t.timestamps
    end
    add_index :ai_runs, :public_id, unique: true
    add_index :ai_runs, %i[record_type record_id]
    add_index :ai_runs, %i[status task_type]

    create_table :audit_events do |t|
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :record_type, null: false
      t.bigint :record_id
      t.string :record_public_id
      t.json :before_data
      t.json :after_data
      t.string :ip_address
      t.string :request_id
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :audit_events, %i[record_type record_id]
    add_index :audit_events, :occurred_at
    add_index :audit_events, :request_id

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body
      t.string :link
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, :public_id, unique: true
    add_index :notifications, %i[user_id read_at]
  end
end
