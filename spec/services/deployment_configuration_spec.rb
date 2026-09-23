require "rails_helper"

RSpec.describe DeploymentConfiguration do
  let(:environment) do
    { "DATABASE_URL" => "postgres://user:synthetic-password@db.example.test/business",
      "QUEUE_DATABASE_URL" => "postgres://user:synthetic-password@db.example.test/queue",
      "CACHE_DATABASE_URL" => "postgres://user:synthetic-password@db.example.test/cache",
      "CABLE_DATABASE_URL" => "postgres://user:synthetic-password@db.example.test/cable",
      "APP_HOST" => "work.example.test", "APP_HOSTS" => "work.example.test", "SECRET_KEY_BASE" => "synthetic-secret",
      "S3_REGION" => "example-region", "S3_BUCKET" => "private-example" }
  end

  it "accepts separate PostgreSQL databases on one managed instance" do
    expect(described_class.validate!(environment)).to be(true)
  end

  it "defaults to HTTPS and requires exact explicit demo opt-in" do
    expect(described_class.http_demo?(environment)).to be(false)
    expect(described_class.http_demo?(environment.merge("ALLOW_HTTP_DEMO" => "false"))).to be(false)
    expect(described_class.http_demo?(environment.merge("ALLOW_HTTP_DEMO" => "true"))).to be(true)
    expect { described_class.validate!(environment.merge("FORCE_SSL" => "false")) }.to raise_error(described_class::Invalid, /explicit/)
  end

  it "rejects HTTP without synthetic-data acknowledgement" do
    expect { described_class.validate!(environment.merge("ALLOW_HTTP_DEMO" => "true")) }.to raise_error(described_class::Invalid, /DEMO_DATA_ONLY/)
    expect(described_class.validate!(environment.merge("ALLOW_HTTP_DEMO" => "true", "DEMO_DATA_ONLY" => "true"))).to be(true)
  end

  it "fails before startup for missing or shared job databases without exposing credentials" do
    expect { described_class.validate!(environment.except("QUEUE_DATABASE_URL")) }.to raise_error(described_class::Invalid, /QUEUE_DATABASE_URL/)
    expect { described_class.validate!(environment.merge("QUEUE_DATABASE_URL" => environment["DATABASE_URL"])) }.to raise_error(described_class::Invalid, /distinct databases/)
    expect { described_class.validate!(environment.merge("DATABASE_URL" => "bad synthetic-password uri")) }.to raise_error do |error|
      expect(error.message).not_to include("synthetic-password")
    end
  end

  it "does not allow copying the development local-storage setting to production" do
    expect { described_class.validate!(environment.merge("ACTIVE_STORAGE_SERVICE" => "local")) }.to raise_error(described_class::Invalid, /private cloud storage/)
  end

  it "keeps queue, cache and cable migrations separate from the business schema" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SCHEMA").and_return(nil)
    configuration = Rails.application.config.database_configuration.fetch("production")
    %w[queue cache cable].each do |name|
      expect(configuration.fetch(name).fetch("migrations_paths")).to eq("db/#{name}_migrate")
      db_config = ActiveRecord::DatabaseConfigurations.new("production" => { name => configuration.fetch(name) }).configs_for(env_name: "production", name: name)
      path = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config)
      expect(Pathname.new(path).expand_path).to eq(Rails.root.join("db/#{name}_schema.rb").expand_path)
      expect(File).to exist(path)
    end
  end

  it "does not let PostgreSQL regression overwrite the portable SQLite schema" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TEST_DATABASE_URL").and_return("postgresql://localhost/synthetic_test")
    configuration = Rails.application.config.database_configuration.fetch("test")
    expect(configuration.fetch("schema_dump")).to be(false)
    db_config = ActiveRecord::DatabaseConfigurations.new("test" => configuration).configs_for(env_name: "test").first
    expect(ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config)).to be_nil
    expect(Rails.root.join("db/schema.rb").read).not_to include("::numeric", "::text", "::character varying")
  end
end
