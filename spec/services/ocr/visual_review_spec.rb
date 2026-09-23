require "rails_helper"

RSpec.describe Ocr::VisualReview do
  let(:review) do
    { "status" => "checked", "signature_labels_examined" => 1, "omitted_candidates" => 0,
      "candidates" => [ { "kind" => "signature_ink_candidate", "bbox" => [ 0.1, 0.2, 0.4, 0.5 ], "basis" => "墨迹非鉴真" } ] }
  end

  it "仅允许有限的规范化坐标、已知候选类型与受限条数" do
    expect(described_class.valid?(review)).to be(true)
    [ nil, {}, review.merge("status" => "verified"), review.merge("candidates" => "bad"),
      review.merge("candidates" => review["candidates"] * 21), review.merge("signature_labels_examined" => -1) ].each do |invalid|
      expect(described_class.valid?(invalid)).to be(false)
    end
    [ [ 0, 0, 1 ], [ -1, 0, 1, 1 ], [ 1, 0, 0, 1 ], [ 0, 0, Float::INFINITY, 1 ], [ "0", 0, 1, 1 ] ].each do |box|
      candidate = review["candidates"].first.merge("bbox" => box)
      expect(described_class.valid?(review.merge("candidates" => [ candidate ]))).to be(false)
    end
  end
end
