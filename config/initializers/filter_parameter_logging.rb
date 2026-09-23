# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :ai_api_key, :ocr_worker_token, :s3_secret_access_key,
  :content, :body, :summary, :note, :comment, :ocr_text, :raw_output, :output, :metadata, :analysis_data, :file
]
