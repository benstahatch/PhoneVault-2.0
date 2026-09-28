class DevicesController < ApplicationController
  def index
    @devices = current_user.devices
  end

  def new
    @device = current_user.devices.new
  end

  def create
    device_params = params.expect(device: %i[name device_type])
    @device = current_user.devices.new(device_params)

    if @device.save
      redirect_to devices_path, notice: "Device registered successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end
end
