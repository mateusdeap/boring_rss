class PreferencesController < ApplicationController
  def update
    Current.user.update!(theme_params)
    redirect_back fallback_location: root_path
  end

  private

  def theme_params
    params.expect(user: [ :theme ])
  end
end
