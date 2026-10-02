require "rails_helper"

RSpec.describe "Home", type: :request do
  it "lists every tool" do
    get root_path

    expect(response).to have_http_status(:ok)
    Tool.all.each { |tool| expect(response.body).to include(CGI.escapeHTML(tool.title)) }
  end

  it "marks tools without a path as coming soon and does not link them" do
    get root_path

    expect(response.body.scan("Coming soon").size).to eq(Tool.all.count { |t| !t.live? })
  end
end
