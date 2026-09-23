require Rails.root.join("lib/deployment_configuration")

# Rails explicitly uses SECRET_KEY_BASE_DUMMY for offline asset builds, not server startup.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  DeploymentConfiguration.validate!(ENV)
end
