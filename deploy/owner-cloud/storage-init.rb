client = Aws::S3::Client.new(region: ENV.fetch("S3_REGION"), endpoint: ENV.fetch("S3_ENDPOINT"),
  access_key_id: ENV.fetch("S3_ACCESS_KEY_ID"), secret_access_key: ENV.fetch("S3_SECRET_ACCESS_KEY"), force_path_style: true)
begin
  client.head_bucket(bucket: ENV.fetch("S3_BUCKET"))
rescue Aws::S3::Errors::NotFound
  client.create_bucket(bucket: ENV.fetch("S3_BUCKET"))
end
puts "Private storage ready"
