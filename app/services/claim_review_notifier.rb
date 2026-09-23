class ClaimReviewNotifier
  def self.call(claim)
    recipients = claim.project.members.to_a + [ claim.project.owner ]
    recipients.compact.uniq.select(&:active?).each do |user|
      next unless ProjectPolicy.new(user, claim.project).show?
      should_notify = if claim.status == "supplement_required"
        ClaimPolicy.new(user, claim).update?
      else
        ClaimPolicy.new(user, claim).review?
      end
      next unless should_notify

      user.notifications.create!(
        kind: "claim.review",
        title: claim.status == "supplement_required" ? "债权资料需要补正" : "债权待您复核",
        body: "#{claim.creditor_name} · #{ClaimReviewFlow::STAGE_LABELS[claim.review_stage]}",
        link: Rails.application.routes.url_helpers.claim_path(claim)
      )
    end
  end
end
