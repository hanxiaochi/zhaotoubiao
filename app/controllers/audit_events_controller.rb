class AuditEventsController < ApplicationController
  def index
    authorize AuditEvent
    @events = AuditEvent.includes(:actor).order(occurred_at: :desc).limit(200)
  end
end
