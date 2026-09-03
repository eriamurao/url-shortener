class ApplicationController < ActionController::API
  around_action :route_to_correct_database

  private

  def route_to_correct_database
    role = request.get? || request.head? ? :reading : :writing
    ActiveRecord::Base.connected_to(role: role) do
      yield
    end
  end
end
