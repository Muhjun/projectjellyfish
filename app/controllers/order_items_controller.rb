class OrderItemsController < ApplicationController
  after_action :verify_authorized

  before_action :load_order_item, only: [:show, :destroy, :update, :start_service, :stop_service]
  before_action :load_order_item_for_provision_update, only: [:provision_update]

  api :GET, '/order_items/:id', 'Shows order item with :id'
  param :includes, Array, required: false, in: %w(product)
  param :id, :number, required: true
  error code: 404, desc: MissingRecordDetection::Messages.not_found

  def show
    authorize @order_item
    respond_with_params @order_item
  end

  api :DELETE, '/order_items/:id', 'Deletes order item with :id'
  param :id, :number, required: true
  error code: 404, desc: MissingRecordDetection::Messages.not_found

  def destroy
    authorize @order_item
    @order_item.destroy
    respond_with @order_item
  end

  api :PUT, '/order_items/:id', 'Updates order item with :id'
  param :id, :number, required: true
  param :provision_status, %w(ok warning critical unknown pending)
  param :hourly_price, :number, required: false
  param :monthly_price, :number, required: false
  param :setup_price, :number, required: false
  error code: 404, desc: MissingRecordDetection::Messages.not_found
  error code: 422, desc: ParameterValidation::Messages.missing

  def update
    authorize @order_item
    @order_item.update_attributes order_item_params
    respond_with @order_item
  end

  api :PUT, '/order_items/:id/start_service', 'Starts service for order item'
  param :id, :number, required: true

  def start_service
    authorize OrderItem
    # TODO: Direct ManageIQ to pass along a start request
    render nothing: true, status: :ok
  end

  api :PUT, '/order_items/:id/stop_service', 'Stops service for order item'
  param :id, :number, required: true

  def stop_service
    authorize OrderItem
    # TODO: Direct ManageIQ to pass along a stop request
    render nothing: true, status: :ok
  end

  api :PUT, '/order_items/:id/retire_service'
  param :id, :number, required: true

  def retire_service
    authorize OrderItem
    render nothing: true, status: :ok
    RetireWorker.new(params[:id]).delay(queue: 'retire_request').perform
  end

  api :PUT, '/order_items/:id/provision_update', 'Updates an order item from ManageIQ'
  param :id, :number, required: true, desc: 'Order Item ID'
  param :status, String, required: true, desc: 'Status of the provision request'
  param :message, String, required: true, desc: 'Any messages from ManageIQ'
  param :info, Hash, required: true, desc: 'Informational payload from ManageIQ' do
    param :uuid, String, required: true, desc: 'V4 UUID Generated for order item upon creation'
    param :provision_status, String, required: true, desc: 'Status of the provision request'
    param :miq_id, :number, required: false, desc: 'The unique ID from ManageIQ'
  end

  error code: 404, desc: MissingRecordDetection::Messages.not_found
  error code: 422, desc: ParameterValidation::Messages.missing

  def provision_update
    authorize @order_item

    ignore = %w(uuid order_item provision_status)
    params[:info].each do |key, value|
      next if ignore.include?(key) || value.blank?
      @order_item.provision_derivations.build(order_item_id: params[:id], name: key, value: value)
    end

    @order_item.update_attributes order_item_params_for_provision_update
    respond_with @order_item
  end

  private

  def order_item_params
    params.permit(:uuid, :hourly_price, :monthly_price, :setup_price)
  end

  def load_order_item
    @order_item = OrderItem.find params.require(:id)
  end

  def order_item_params_for_provision_update
    params.require(:info).permit(:miq_id, :provision_status).merge(payload_response: ActionController::Parameters.new(JSON.parse(request.body.read)))
  end

  def load_order_item_for_provision_update
    @order_item = OrderItem.where(id: params.require(:id), uuid: params.require(:info)[:uuid]).first!
  end
end
