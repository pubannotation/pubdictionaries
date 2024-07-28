class Users::RegistrationsController < Devise::RegistrationsController
  before_action :validate_recaptcha, only: [:create]

  private

  def validate_recaptcha
    self.resource = resource_class.new(sign_up_params)
    resource.validate # Without this, all validations will not be displayed.

    unless verify_recaptcha(model: resource)
      respond_with_navigational(resource) { render :new }
    end
  end
end
