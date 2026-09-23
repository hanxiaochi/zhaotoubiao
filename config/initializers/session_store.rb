require Rails.root.join("lib/deployment_configuration")

Rails.application.config.session_store(
  :cookie_store,
  key: "_donghua_ai_session",
  secure: Rails.env.production? && !DeploymentConfiguration.http_demo?(ENV),
  httponly: true,
  same_site: :lax,
  expire_after: 12.hours
)
