module Tender
  class SyncSourceJob < ApplicationJob
    queue_as :background

    def perform(source_id)
      source = TenderSource.find(source_id)
      items = SourceClient.new(source).fetch
      synced = 0
      TenderNotice.transaction do
        items.each do |attributes|
          notice = source.tender_notices.find_or_initialize_by(external_id: attributes.fetch(:external_id))
          notice.assign_attributes(attributes.except(:external_id))
          notice.status ||= "new"
          notice.save!
          synced += 1
        end
        source.update!(last_synced_at: Time.current)
        Audit::Recorder.call(action: "tender_source.sync", record: source, after_data: { synced: synced, last_synced_at: source.last_synced_at })
      end
    rescue SourceClient::SourceError => error
      Audit::Recorder.call(action: "tender_source.sync_failed", record: source, after_data: { error_class: error.class.name, message: error.message.first(160) }) if source
      raise
    end
  end
end
