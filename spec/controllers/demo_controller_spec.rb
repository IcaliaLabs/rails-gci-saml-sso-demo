require 'rails_helper'

RSpec.describe DemoController, type: :controller do

  describe "GET #landing" do
    it "returns http success" do
      get :landing
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET #protected_area" do
    it "returns http success" do
      get :protected_area
      expect(response).to have_http_status(:success)
    end
  end

end
