require "rails_helper"

RSpec.describe "系统初始化与登录", type: :request do
  it "登录页和工作看板显式加载主样式，不依赖构建目录自动发现" do
    user = create_user(admin: true)
    get new_session_path
    styles = Nokogiri::HTML(response.body).css('link[rel="stylesheet"]').map { |link| link['href'] }
    expect(styles).to include(a_string_matching(%r{/assets/tailwind(?:-[a-z0-9]+)?\.css}))

    post session_path, params: { email: user.email, password: AuthenticationHelpers::TEST_PASSWORD }
    get root_path
    styles = Nokogiri::HTML(response.body).css('link[rel="stylesheet"]').map { |link| link['href'] }
    expect(styles).to include(a_string_matching(%r{/assets/tailwind(?:-[a-z0-9]+)?\.css}))
  end

  it "只允许首位用户完成初始化并获得管理员角色" do
    expect do
      post setup_path, params: { user: { name: "系统管理员", email: "admin@donghua.test", password: AuthenticationHelpers::TEST_PASSWORD, password_confirmation: AuthenticationHelpers::TEST_PASSWORD } }
    end.to change(User, :count).by(1).and change(AuditEvent, :count).by(1)

    user = User.find_by!(email: "admin@donghua.test")
    expect(user).to be_admin
    expect(Department.pluck(:code)).to contain_exactly("bankruptcy", "tender", "audit")
    expect(response).to redirect_to(root_path)

    delete session_path
    get new_setup_path
    expect(response).to redirect_to(new_session_path)
  end

  it "拒绝错误密码并允许有效用户登录" do
    user = create_user(admin: true)

    post session_path, params: { email: user.email, password: "wrong-password" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("邮箱或密码不正确")

    post session_path, params: { email: user.email.upcase, password: AuthenticationHelpers::TEST_PASSWORD }
    expect(response).to redirect_to(root_path)
    expect(user.reload.last_sign_in_at).to be_present
  end

  it "初始化事务失败不签发登录状态，页面仍可重新初始化" do
    allow(Audit::Recorder).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))
    post setup_path, params: { user: { name: "回滚验收", email: "rollback@example.test", password: AuthenticationHelpers::TEST_PASSWORD } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(User.count).to eq(0)
    expect(request.session[:user_id]).to be_nil
    get root_path
    expect(response).to redirect_to(new_setup_path)
  end

  it "并发请求在事务内发现初始化已完成时不创建第二位管理员" do
    allow(SystemBootstrap).to receive(:call).and_raise(SystemBootstrap::AlreadyInitialized)
    post setup_path, params: { user: { name: "并发验收", email: "race@example.test", password: AuthenticationHelpers::TEST_PASSWORD } }
    expect(response).to redirect_to(new_session_path)
    expect(User.count).to eq(0)
    expect(request.session[:user_id]).to be_nil
  end
end
