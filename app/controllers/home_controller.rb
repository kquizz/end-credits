class HomeController < ApplicationController
  def index
    @tools = Tool.all
  end
end
