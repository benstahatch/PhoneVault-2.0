# For controllers nested under /devices/:device_id. Looks the device up through
# current_user, so another user's device raises RecordNotFound (a 404).
module DeviceScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_device
  end

  private

  def set_device
    @device = current_user.devices.find(params[:device_id])
  end
end
