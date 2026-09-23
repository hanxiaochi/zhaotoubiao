require "rails_helper"

RSpec.describe "安全响应头与会话", type: :request do
  it "为页面响应设置 CSP、点击劫持和内容嗅探保护" do
    get new_setup_path

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Security-Policy"]).to include("default-src 'self'")
    expect(response.headers["Content-Security-Policy"]).to include("frame-ancestors 'none'")
    expect(response.headers["X-Frame-Options"]).to eq("DENY")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
  end

  it "设置 HttpOnly 与 SameSite 会话 Cookie" do
    post setup_path, params: { user: { name: "Cookie 管理员", email: "cookie-admin@example.com", password: AuthenticationHelpers::TEST_PASSWORD, password_confirmation: AuthenticationHelpers::TEST_PASSWORD } }

    cookie = response.headers["Set-Cookie"]
    expect(cookie.downcase).to include("httponly")
    expect(cookie.downcase).to include("samesite=lax")
  end
end
