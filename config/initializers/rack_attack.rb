class Rack::Attack
  throttle("login/ip", limit: 10, period: 1.minute) do |request|
    request.ip if request.post? && request.path == "/session"
  end

  throttle("login/email", limit: 6, period: 5.minutes) do |request|
    request.params["email"].to_s.strip.downcase if request.post? && request.path == "/session"
  end

  throttle("writes/ip", limit: 300, period: 5.minutes) do |request|
    request.ip if request.post? || request.patch? || request.put? || request.delete?
  end

  throttle("uploads/ip", limit: 30, period: 10.minutes) do |request|
    request.ip if request.post? && request.path.match?(%r{/projects/[^/]+/project_documents})
  end

  throttle("ai/ip", limit: 20, period: 10.minutes) do |request|
    request.ip if request.post? && request.path.end_with?("/ai_suggest")
  end

  self.throttled_responder = lambda do |_request|
    [ 429, { "Content-Type" => "text/plain; charset=utf-8", "Retry-After" => "60" }, [ "请求过于频繁，请稍后重试。" ] ]
  end
end
