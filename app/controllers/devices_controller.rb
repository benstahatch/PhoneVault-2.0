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
      record_security_event("DEVICE_REGISTERED", current_user)
      redirect_to devices_path, notice: "Device registered successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @device = find_device
  end

  def update
    @device = find_device

    # only the name can change; the device type stays what it was registered as
    if @device.update(params.expect(device: %i[name]))
      redirect_to devices_path, notice: "Device renamed to #{@device.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # looking up through current_user means another user's device raises RecordNotFound (a 404)
  def find_device
    current_user.devices.find(params[:id])
  end
end
