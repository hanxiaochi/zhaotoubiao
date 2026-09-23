module Tender
  class SyncAllSourcesJob < ApplicationJob
    queue_as :background

    def perform
      TenderSource.where(active: true, authorized: true, access_mode: %w[public_api licensed_api]).find_each do |source|
        SyncSourceJob.perform_later(source.id)
      end
    end
  end
end
