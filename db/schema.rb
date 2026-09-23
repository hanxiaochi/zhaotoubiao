# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_07_032000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "evidence_refs", default: [], null: false
    t.json "input_scope", default: {}, null: false
    t.integer "input_tokens"
    t.string "model"
    t.text "output"
    t.integer "output_tokens"
    t.integer "project_id", null: false
    t.string "prompt_sha256"
    t.string "provider"
    t.string "public_id", null: false
    t.text "raw_output"
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.integer "requested_by_id", null: false
    t.text "review_note"
    t.datetime "reviewed_at"
    t.integer "reviewed_by_id"
    t.string "source_fingerprint"
    t.string "status", default: "queued", null: false
    t.string "task_type", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_ai_runs_on_project_id"
    t.index ["public_id"], name: "index_ai_runs_on_public_id", unique: true
    t.index ["record_type", "record_id"], name: "index_ai_runs_on_record_type_and_record_id"
    t.index ["requested_by_id"], name: "index_ai_runs_on_requested_by_id"
    t.index ["reviewed_by_id"], name: "index_ai_runs_on_reviewed_by_id"
    t.index ["status", "task_type"], name: "index_ai_runs_on_status_and_task_type"
    t.index ["status", "updated_at"], name: "index_ai_runs_on_status_and_updated_at"
  end

  create_table "asset_versions", force: :cascade do |t|
    t.decimal "appraisal_value", precision: 18, scale: 2
    t.integer "asset_id", null: false
    t.string "change_reason", null: false
    t.integer "changed_by_id", null: false
    t.datetime "created_at", null: false
    t.json "snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_asset_versions_on_asset_id"
    t.index ["changed_by_id"], name: "index_asset_versions_on_changed_by_id"
  end

  create_table "assets", force: :cascade do |t|
    t.string "address"
    t.string "appraisal_org"
    t.decimal "appraisal_value", precision: 18, scale: 2
    t.string "asset_code", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "disposal_status", default: "pending", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.string "rights_no"
    t.string "source_reference"
    t.datetime "updated_at", null: false
    t.integer "updated_by_id", null: false
    t.index ["project_id", "asset_code"], name: "index_assets_on_project_id_and_asset_code", unique: true
    t.index ["project_id", "rights_no"], name: "index_assets_on_project_id_and_rights_no"
    t.index ["project_id"], name: "index_assets_on_project_id"
    t.index ["public_id"], name: "index_assets_on_public_id", unique: true
    t.index ["updated_by_id"], name: "index_assets_on_updated_by_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.json "after_data"
    t.json "before_data"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "occurred_at", null: false
    t.bigint "record_id"
    t.string "record_public_id"
    t.string "record_type", null: false
    t.string "request_id"
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["occurred_at"], name: "index_audit_events_on_occurred_at"
    t.index ["record_type", "record_id"], name: "index_audit_events_on_record_type_and_record_id"
    t.index ["request_id"], name: "index_audit_events_on_request_id"
  end

  create_table "bid_analyses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "criteria", default: [], null: false
    t.json "disqualification_clauses", default: [], null: false
    t.json "outline", default: [], null: false
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.json "qualification_requirements", default: [], null: false
    t.text "review_note"
    t.datetime "reviewed_at"
    t.integer "reviewed_by_id"
    t.json "risks", default: [], null: false
    t.decimal "simulated_score", precision: 8, scale: 2
    t.string "status", default: "pending", null: false
    t.json "suggested_tasks", default: [], null: false
    t.json "time_nodes", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_bid_analyses_on_project_id"
    t.index ["public_id"], name: "index_bid_analyses_on_public_id", unique: true
    t.index ["reviewed_by_id"], name: "index_bid_analyses_on_reviewed_by_id"
  end

  create_table "bid_evidences", force: :cascade do |t|
    t.integer "bid_analysis_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "criterion", null: false
    t.integer "library_entry_id", null: false
    t.text "note", null: false
    t.string "page_reference", null: false
    t.string "public_id", null: false
    t.json "source_snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["bid_analysis_id"], name: "index_bid_evidences_on_bid_analysis_id"
    t.index ["created_by_id"], name: "index_bid_evidences_on_created_by_id"
    t.index ["library_entry_id"], name: "index_bid_evidences_on_library_entry_id"
    t.index ["public_id"], name: "index_bid_evidences_on_public_id", unique: true
  end

  create_table "bid_scores", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.decimal "awarded", precision: 7, scale: 2, null: false
    t.integer "bid_analysis_id", null: false
    t.datetime "created_at", null: false
    t.string "criterion", null: false
    t.text "evidence_exception"
    t.decimal "maximum", precision: 7, scale: 2, null: false
    t.string "page_reference"
    t.integer "project_document_id"
    t.string "public_id", null: false
    t.text "rationale", null: false
    t.boolean "requires_evidence", default: true, null: false
    t.text "scoring_rule"
    t.datetime "updated_at", null: false
    t.integer "updated_by_id", null: false
    t.index ["bid_analysis_id", "criterion"], name: "index_bid_scores_on_bid_analysis_id_and_criterion", unique: true
    t.index ["bid_analysis_id"], name: "index_bid_scores_on_bid_analysis_id"
    t.index ["project_document_id"], name: "index_bid_scores_on_project_document_id"
    t.index ["public_id"], name: "index_bid_scores_on_public_id", unique: true
    t.index ["updated_by_id"], name: "index_bid_scores_on_updated_by_id"
    t.check_constraint "maximum > 0 AND maximum <= 100 AND awarded >= 0 AND awarded <= maximum", name: "bid_scores_valid_range"
  end

  create_table "bid_simulations", force: :cascade do |t|
    t.string "basis_sha256", null: false
    t.integer "bid_analysis_id", null: false
    t.boolean "confirmed_complete", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "public_id", null: false
    t.json "results", default: [], null: false
    t.json "rubric", default: [], null: false
    t.integer "source_id", null: false
    t.text "source_text", null: false
    t.string "source_title", null: false
    t.string "source_type", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.decimal "total_score", precision: 7, scale: 2
    t.datetime "updated_at", null: false
    t.json "warnings", default: [], null: false
    t.index ["bid_analysis_id"], name: "index_bid_simulations_on_bid_analysis_id"
    t.index ["created_by_id"], name: "index_bid_simulations_on_created_by_id"
    t.index ["public_id"], name: "index_bid_simulations_on_public_id", unique: true
    t.index ["source_type", "source_id"], name: "index_bid_simulations_on_source"
  end

  create_table "claim_checklists", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "claim_type", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.json "material_types", default: [], null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_claim_checklists_on_created_by_id"
    t.index ["project_id", "claim_type", "active"], name: "index_claim_checklists_on_project_id_and_claim_type_and_active"
    t.index ["project_id", "name"], name: "index_claim_checklists_on_project_id_and_name", unique: true
    t.index ["project_id"], name: "index_claim_checklists_on_project_id"
    t.index ["public_id"], name: "index_claim_checklists_on_public_id", unique: true
  end

  create_table "claim_materials", force: :cascade do |t|
    t.boolean "authorization_complete"
    t.string "authorization_requirement", default: "undetermined", null: false
    t.integer "checked_by_id"
    t.integer "claim_id", null: false
    t.datetime "created_at", null: false
    t.decimal "extraction_confidence", precision: 5, scale: 2
    t.string "material_requirement", default: "required", null: false
    t.string "material_type", null: false
    t.text "note"
    t.string "page_reference"
    t.boolean "present", default: false, null: false
    t.integer "project_document_id"
    t.text "requirement_note"
    t.boolean "seal_detected"
    t.string "seal_requirement", default: "undetermined", null: false
    t.boolean "signature_detected"
    t.string "signature_requirement", default: "undetermined", null: false
    t.datetime "updated_at", null: false
    t.index ["checked_by_id"], name: "index_claim_materials_on_checked_by_id"
    t.index ["claim_id", "material_type"], name: "index_claim_materials_on_claim_id_and_material_type", unique: true
    t.index ["claim_id"], name: "index_claim_materials_on_claim_id"
    t.index ["project_document_id"], name: "index_claim_materials_on_project_document_id"
    t.check_constraint "authorization_requirement IN ('required', 'not_required', 'undetermined')", name: "claim_materials_authorization_requirement_valid"
    t.check_constraint "material_requirement IN ('required', 'not_required', 'undetermined')", name: "claim_materials_material_requirement_valid"
    t.check_constraint "seal_requirement IN ('required', 'not_required', 'undetermined')", name: "claim_materials_seal_requirement_valid"
    t.check_constraint "signature_requirement IN ('required', 'not_required', 'undetermined')", name: "claim_materials_signature_requirement_valid"
  end

  create_table "claim_reviews", force: :cascade do |t|
    t.string "basis_sha256"
    t.integer "claim_id", null: false
    t.text "comment", null: false
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.json "evidence", default: [], null: false
    t.json "evidence_snapshot", default: {}, null: false
    t.integer "reviewer_id", null: false
    t.string "stage", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id", "stage", "created_at"], name: "index_claim_reviews_on_claim_id_and_stage_and_created_at"
    t.index ["claim_id"], name: "index_claim_reviews_on_claim_id"
    t.index ["reviewer_id"], name: "index_claim_reviews_on_reviewer_id"
  end

  create_table "claim_supplements", force: :cascade do |t|
    t.integer "claim_id", null: false
    t.datetime "created_at", null: false
    t.json "material_snapshot", default: [], null: false
    t.text "note", null: false
    t.string "review_stage", null: false
    t.integer "submitted_by_id", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id"], name: "index_claim_supplements_on_claim_id"
    t.index ["submitted_by_id"], name: "index_claim_supplements_on_submitted_by_id"
  end

  create_table "claims", force: :cascade do |t|
    t.json "analysis_data", default: {}, null: false
    t.decimal "claim_amount", precision: 18, scale: 2, default: "0.0", null: false
    t.string "claimed_type", default: "unknown", null: false
    t.decimal "completeness_score", precision: 5, scale: 2
    t.string "contact_name"
    t.string "contact_phone"
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "creditor_name", null: false
    t.string "currency", default: "CNY", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.string "recommended_type"
    t.string "review_stage", default: "initial", null: false
    t.string "risk_level", default: "unrated", null: false
    t.string "status", default: "received", null: false
    t.text "summary"
    t.string "unified_code"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_claims_on_created_by_id"
    t.index ["project_id", "creditor_name"], name: "index_claims_on_project_id_and_creditor_name"
    t.index ["project_id", "review_stage", "status"], name: "index_claims_on_project_id_and_review_stage_and_status"
    t.index ["project_id", "status"], name: "index_claims_on_project_id_and_status"
    t.index ["project_id"], name: "index_claims_on_project_id"
    t.index ["public_id"], name: "index_claims_on_public_id", unique: true
  end

  create_table "departments", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_departments_on_code", unique: true
    t.index ["public_id"], name: "index_departments_on_public_id", unique: true
  end

  create_table "fees", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "fee_type", null: false
    t.string "invoice_status", default: "not_issued", null: false
    t.text "note"
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.decimal "receivable", precision: 18, scale: 2, default: "0.0", null: false
    t.decimal "received", precision: 18, scale: 2, default: "0.0", null: false
    t.date "received_on"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_fees_on_created_by_id"
    t.index ["project_id", "fee_type"], name: "index_fees_on_project_id_and_fee_type"
    t.index ["project_id"], name: "index_fees_on_project_id"
    t.index ["public_id"], name: "index_fees_on_public_id", unique: true
  end

  create_table "generated_documents", force: :cascade do |t|
    t.json "ai_warnings", default: [], null: false
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.integer "bid_analysis_id"
    t.json "bid_basis_snapshot", default: {}, null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "kind", null: false
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.text "review_note"
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_generated_documents_on_approved_by_id"
    t.index ["bid_analysis_id"], name: "index_generated_documents_on_bid_analysis_id"
    t.index ["created_by_id"], name: "index_generated_documents_on_created_by_id"
    t.index ["project_id"], name: "index_generated_documents_on_project_id"
    t.index ["public_id"], name: "index_generated_documents_on_public_id", unique: true
  end

  create_table "intake_items", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "custodian"
    t.string "name", null: false
    t.text "note"
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.datetime "received_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_intake_items_on_created_by_id"
    t.index ["project_id", "category", "status"], name: "index_intake_items_on_project_id_and_category_and_status"
    t.index ["project_id"], name: "index_intake_items_on_project_id"
    t.index ["public_id"], name: "index_intake_items_on_public_id", unique: true
  end

  create_table "library_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.text "description", null: false
    t.date "expires_on"
    t.date "issued_on"
    t.string "kind", null: false
    t.string "organization", null: false
    t.string "public_id", null: false
    t.string "reference_number"
    t.integer "revision_number", default: 1, null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_library_entries_on_created_by_id"
    t.index ["kind", "status"], name: "index_library_entries_on_kind_and_status"
    t.index ["public_id"], name: "index_library_entries_on_public_id", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "deduplication_key"
    t.string "kind", null: false
    t.string "link"
    t.string "public_id", null: false
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["deduplication_key"], name: "index_notifications_on_deduplication_key", unique: true
    t.index ["public_id"], name: "index_notifications_on_public_id", unique: true
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "project_documents", force: :cascade do |t|
    t.string "analysis_status", default: "pending", null: false
    t.bigint "byte_size"
    t.string "category", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.string "ocr_attempt_token"
    t.string "ocr_status", default: "pending", null: false
    t.text "ocr_text"
    t.string "original_filename", null: false
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.string "sha256"
    t.string "status", default: "uploaded", null: false
    t.datetime "updated_at", null: false
    t.integer "uploaded_by_id", null: false
    t.index ["ocr_status", "updated_at"], name: "index_project_documents_on_ocr_status_and_updated_at"
    t.index ["project_id", "category"], name: "index_project_documents_on_project_id_and_category"
    t.index ["project_id"], name: "index_project_documents_on_project_id"
    t.index ["public_id"], name: "index_project_documents_on_public_id", unique: true
    t.index ["sha256"], name: "index_project_documents_on_sha256"
    t.index ["uploaded_by_id"], name: "index_project_documents_on_uploaded_by_id"
  end

  create_table "project_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "membership_role", default: "member", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["project_id", "user_id"], name: "index_project_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "project_milestones", force: :cascade do |t|
    t.date "completed_on"
    t.datetime "created_at", null: false
    t.date "due_on"
    t.text "note"
    t.integer "owner_id"
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.string "stage", null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_project_milestones_on_owner_id"
    t.index ["project_id", "status", "due_on"], name: "index_project_milestones_on_project_id_and_status_and_due_on"
    t.index ["project_id"], name: "index_project_milestones_on_project_id"
    t.index ["public_id"], name: "index_project_milestones_on_public_id", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.text "archive_reason"
    t.datetime "archived_at"
    t.integer "archived_by_id"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "department_id"
    t.text "description"
    t.date "due_date"
    t.integer "lock_version", default: 0, null: false
    t.json "metadata", default: {}, null: false
    t.string "name", null: false
    t.integer "owner_id"
    t.string "project_type", null: false
    t.string "public_id", null: false
    t.date "start_date"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["archived_by_id"], name: "index_projects_on_archived_by_id"
    t.index ["code"], name: "index_projects_on_code", unique: true
    t.index ["department_id"], name: "index_projects_on_department_id"
    t.index ["owner_id"], name: "index_projects_on_owner_id"
    t.index ["project_type", "status"], name: "index_projects_on_project_type_and_status"
    t.index ["public_id"], name: "index_projects_on_public_id", unique: true
  end

  create_table "roles", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.json "permissions", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_roles_on_code", unique: true
  end

  create_table "tender_notices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deadline_at"
    t.string "external_id"
    t.string "industry"
    t.string "public_id", null: false
    t.datetime "published_at"
    t.string "region"
    t.string "status", default: "new", null: false
    t.json "tags", default: [], null: false
    t.integer "tender_source_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["public_id"], name: "index_tender_notices_on_public_id", unique: true
    t.index ["status", "deadline_at"], name: "index_tender_notices_on_status_and_deadline_at"
    t.index ["tender_source_id", "external_id"], name: "index_tender_notices_on_tender_source_id_and_external_id", unique: true
    t.index ["tender_source_id"], name: "index_tender_notices_on_tender_source_id"
  end

  create_table "tender_sources", force: :cascade do |t|
    t.string "access_mode", default: "public_api", null: false
    t.boolean "active", default: true, null: false
    t.boolean "authorized", default: false, null: false
    t.string "base_url", null: false
    t.datetime "created_at", null: false
    t.string "credential_env_key"
    t.json "filters", default: {}, null: false
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.string "public_id", null: false
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_tender_sources_on_public_id", unique: true
  end

  create_table "tender_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.string "name", null: false
    t.string "project_category", null: false
    t.string "public_id", null: false
    t.integer "revision_number", default: 1, null: false
    t.string "tender_method", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_tender_templates_on_created_by_id"
    t.index ["public_id"], name: "index_tender_templates_on_public_id", unique: true
  end

  create_table "user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "department_id"
    t.string "email", null: false
    t.datetime "last_sign_in_at"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "public_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["department_id"], name: "index_users_on_department_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object", limit: 1073741823
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "workflow_events", force: :cascade do |t|
    t.integer "actor_id", null: false
    t.text "comment", null: false
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_task_id", null: false
    t.index ["actor_id"], name: "index_workflow_events_on_actor_id"
    t.index ["workflow_task_id"], name: "index_workflow_events_on_workflow_task_id"
  end

  create_table "workflow_signatures", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workflow_task_id", null: false
    t.index ["user_id"], name: "index_workflow_signatures_on_user_id"
    t.index ["workflow_task_id", "user_id"], name: "index_workflow_signatures_on_workflow_task_id_and_user_id", unique: true
    t.index ["workflow_task_id"], name: "index_workflow_signatures_on_workflow_task_id"
  end

  create_table "workflow_tasks", force: :cascade do |t|
    t.integer "assignee_id"
    t.string "claim_basis_sha256"
    t.string "claim_review_stage"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "due_at"
    t.integer "project_id", null: false
    t.string "public_id", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.integer "replaces_task_id"
    t.text "restart_reason"
    t.string "stage", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id", "status"], name: "index_workflow_tasks_on_assignee_id_and_status"
    t.index ["assignee_id"], name: "index_workflow_tasks_on_assignee_id"
    t.index ["project_id"], name: "index_workflow_tasks_on_project_id"
    t.index ["public_id"], name: "index_workflow_tasks_on_public_id", unique: true
    t.index ["record_type", "record_id", "claim_review_stage"], name: "index_workflow_claim_stage"
    t.index ["record_type", "record_id"], name: "index_workflow_tasks_on_record_type_and_record_id"
    t.index ["replaces_task_id"], name: "index_workflow_tasks_on_replaces_task_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_runs", "projects"
  add_foreign_key "ai_runs", "users", column: "requested_by_id"
  add_foreign_key "ai_runs", "users", column: "reviewed_by_id"
  add_foreign_key "asset_versions", "assets"
  add_foreign_key "asset_versions", "users", column: "changed_by_id"
  add_foreign_key "assets", "projects"
  add_foreign_key "assets", "users", column: "updated_by_id"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "bid_analyses", "projects"
  add_foreign_key "bid_analyses", "users", column: "reviewed_by_id"
  add_foreign_key "bid_evidences", "bid_analyses"
  add_foreign_key "bid_evidences", "library_entries"
  add_foreign_key "bid_evidences", "users", column: "created_by_id"
  add_foreign_key "bid_scores", "bid_analyses"
  add_foreign_key "bid_scores", "project_documents"
  add_foreign_key "bid_scores", "users", column: "updated_by_id"
  add_foreign_key "bid_simulations", "bid_analyses"
  add_foreign_key "bid_simulations", "users", column: "created_by_id"
  add_foreign_key "claim_checklists", "projects"
  add_foreign_key "claim_checklists", "users", column: "created_by_id"
  add_foreign_key "claim_materials", "claims"
  add_foreign_key "claim_materials", "project_documents"
  add_foreign_key "claim_materials", "users", column: "checked_by_id"
  add_foreign_key "claim_reviews", "claims"
  add_foreign_key "claim_reviews", "users", column: "reviewer_id"
  add_foreign_key "claim_supplements", "claims"
  add_foreign_key "claim_supplements", "users", column: "submitted_by_id"
  add_foreign_key "claims", "projects"
  add_foreign_key "claims", "users", column: "created_by_id"
  add_foreign_key "fees", "projects"
  add_foreign_key "fees", "users", column: "created_by_id"
  add_foreign_key "generated_documents", "bid_analyses"
  add_foreign_key "generated_documents", "projects"
  add_foreign_key "generated_documents", "users", column: "approved_by_id"
  add_foreign_key "generated_documents", "users", column: "created_by_id"
  add_foreign_key "intake_items", "projects"
  add_foreign_key "intake_items", "users", column: "created_by_id"
  add_foreign_key "library_entries", "users", column: "created_by_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "project_documents", "projects"
  add_foreign_key "project_documents", "users", column: "uploaded_by_id"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "project_milestones", "projects"
  add_foreign_key "project_milestones", "users", column: "owner_id"
  add_foreign_key "projects", "departments"
  add_foreign_key "projects", "users", column: "archived_by_id"
  add_foreign_key "projects", "users", column: "owner_id"
  add_foreign_key "tender_notices", "tender_sources"
  add_foreign_key "tender_templates", "users", column: "created_by_id"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "departments"
  add_foreign_key "workflow_events", "users", column: "actor_id"
  add_foreign_key "workflow_events", "workflow_tasks"
  add_foreign_key "workflow_signatures", "users"
  add_foreign_key "workflow_signatures", "workflow_tasks"
  add_foreign_key "workflow_tasks", "projects"
  add_foreign_key "workflow_tasks", "users", column: "assignee_id"
  add_foreign_key "workflow_tasks", "workflow_tasks", column: "replaces_task_id"
end
