require "rails_helper"

RSpec.describe "解析失败和范围限制回显", type: :request do
  it "图像候选保存到文档且显示位置，不自动通过材料人工核验" do
    owner = create_user(admin: true)
    project = create_project(owner: owner)
    claim = project.claims.create!(created_by: owner, creditor_name: "图像核验测试", claim_amount: 100)
    verify_claim_materials(claim)
    material = claim.claim_materials.first!
    material.update!(signature_detected: nil, seal_detected: nil)
    document = material.project_document
    document.update!(content_type: "application/pdf", ocr_status: "queued")
    review = { "status" => "checked", "method" => "local-pixel-heuristics-v1", "signature_labels_examined" => 1, "omitted_candidates" => 2,
      "candidates" => [ { "kind" => "signature_ink_candidate", "bbox" => [ 0.1, 0.2, 0.4, 0.5 ], "basis" => "合成墨迹，仅供核查" } ] }
    client = instance_double(Ocr::Client, extract: { "text" => "签字", "pages" => [ { "page" => 2, "text" => "签字", "visual_review" => review } ] })
    allow(Ocr::Client).to receive(:new).and_return(client)
    Ocr::DocumentJob.perform_now(document.id)
    expect(document.reload.metadata.dig("ocr_pages", 0, "visual_review")).to eq(review)
    expect(material.reload.signature_detected).to be_nil
    expect(material.seal_detected).to be_nil
    sign_in(owner)
    get project_project_document_path(project, document)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("签章图像候选区域", "签字位置附近墨迹", "左 10.0%", "另有 2 处", "下载原件核对签章")
    expect(response.body).to include("不会自动更新债权材料的人工核验状态")
  end

  it "旧结果和非法坐标不渲染虚假的已完成图像检查" do
    owner = create_user(admin: true)
    project = create_project(owner: owner)
    claim = project.claims.create!(created_by: owner, creditor_name: "旧图像结果", claim_amount: 100)
    verify_claim_materials(claim)
    document = claim.claim_materials.first!.project_document
    document.update!(ocr_status: "completed", metadata: { "ocr_pages" => [ { "page" => 1, "visual_review" => { "candidates" => [ { "bbox" => "bad" } ] } } ] })
    sign_in(owner)
    get project_project_document_path(project, document)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("本次结果不含签章图像区域检查")
    expect(response.body).not_to include("签章图像候选区域")
  end

  it "显示失败原因、解析范围及工作表位置，观察者不能发起或归档" do
    owner = create_user(admin: true)
    project = create_project(owner: owner)
    claim = project.claims.create!(created_by: owner, creditor_name: "文档页面验收", claim_amount: 100)
    verify_claim_materials(claim)
    document = claim.claim_materials.first!.project_document
    document.update!(ocr_status: "failed", metadata: { "ocr_error" => "解析超时，请重新发起", "ocr_warnings" => [ "公式未计算结果" ],
      "extracted_fields" => { "claim_amount" => "12345" }, "field_sources" => { "claim_amount" => { "page" => 2, "sheet" => "本金表", "location_kind" => "worksheet" } } })
    observer = create_user(email: "ocr-observer@example.test")
    project.project_memberships.create!(user: observer, membership_role: "observer")
    sign_in(observer)
    get project_project_document_path(project, document)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("解析超时，请重新发起", "公式未计算结果", "工作表：本金表（非打印页码）")
    expect(response.body).not_to include("提取文本/OCR", ">归档<", "据此登记债权")
    expect(response.body).to include("下载原件")
  end
end
