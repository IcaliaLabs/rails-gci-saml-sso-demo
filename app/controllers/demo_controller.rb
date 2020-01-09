class DemoController < ApplicationController
  before_action :authenticate_user!, except: %i[landing]

  def landing
  end

  def protected_area
  end
end
