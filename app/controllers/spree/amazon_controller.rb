##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
class Spree::AmazonController < Spree::StoreController
  helper 'spree/orders'
  before_action :check_current_order
  before_action :gateway, only: [:address, :payment, :delivery]
  before_action :check_amazon_reference_id, only: [:delivery, :complete]
  skip_before_action :verify_authenticity_token, only: %i[payment confirm complete]

  respond_to :json

  def address
    current_order.state = 'address'
    current_order.save!
  end

  def payment
    payment_count = current_order.payments.count
    payment = amazon_payment || current_order.payments.create
    payment.number = "#{params[:order_reference]}_#{payment_count}"
    payment.payment_method = gateway
    payment.source ||= Spree::AmazonTransaction.create(
      order_reference: params[:order_reference],
      order_id: current_order.id,
      retry: current_order.amazon_transactions.unsuccessful.any?
    )

    payment.save!

    render json: {}
  end

  def delivery
    address = SpreeAmazon::Address.find(
      current_order.amazon_order_reference_id,
      gateway: gateway,
      address_consent_token: params[:access_token],
    )

    current_order.state = "address"

    if address
      current_order.email = spree_current_user.try(:email) || "pending@amazon.com"
      update_current_order_address!(address, spree_current_user.try(:ship_address))

      current_order.save!
      current_order.next

      current_order.reload

      if current_order.shipments.empty?
        render plain: 'Not shippable to this address'
      else
        render layout: false
      end
    else
      head :ok
    end
  end

  def confirm
    if !amazon_payment.nil? && current_order.update_from_params(params, permitted_checkout_attributes, request.headers.env)
      while current_order.next && !current_order.confirm?
      end

      update_payment_amount!
      current_order.next! unless current_order.confirm?
      complete
    else
      redirect_to :back
    end
  end

  def complete
    @order = current_order
    authorize!(:edit, @order, cookies.signed[:guest_token])

    unless @order.amazon_transaction.retry
      amazon_response = set_order_reference_details!
      unless amazon_response.constraints.blank?
        redirect_to address_amazon_order_path, notice: amazon_response.constraints and return
      end
    end

    complete_amazon_order!

    if @order.confirm? && @order.next
      @current_order = nil
      flash.notice = Spree.t(:order_processed_successfully)
      flash[:order_completed] = true
      redirect_to spree.order_path(@order)
    else
      amazon_transaction = @order.amazon_transaction
      @order.state = 'cart'
      amazon_transaction.reload
      if amazon_transaction.soft_decline
        @order.save!
        redirect_to address_amazon_order_path, notice: amazon_transaction.message
      else
        @order.amazon_transactions.destroy_all
        @order.save!
        redirect_to cart_path, notice: Spree.t(:order_processed_unsuccessfully)
      end
    end
  end

  def gateway
    @gateway ||= Spree::Gateway::Amazon.for_currency(current_order.currency)
  end

  private

  def amazon_order
    @amazon_order ||= SpreeAmazon::Order.new(
      reference_id: current_order.amazon_order_reference_id,
      gateway: gateway,
    )
  end

  def amazon_payment
    current_order.payments.valid.amazon.first
  end

  def update_payment_amount!
    payment = amazon_payment
    payment.amount = current_order.total
    payment.save!
  end

  def set_order_reference_details!
    amazon_order.set_order_reference_details(
        current_order.total,
        seller_order_id: current_order.number,
        store_name: current_order.store.name,
      )
  end

  def complete_amazon_order!
    confirm_response = amazon_order.confirm
    if confirm_response.success
      amazon_order.fetch
      current_order.email = amazon_order.email
      update_current_order_address!(amazon_order.address)
    end
  end

  def checkout_params
    params.require(:order).permit(permitted_checkout_attributes)
  end

  def update_current_order_address!(amazon_address, spree_user_address = nil)
    if current_order.billing_address.nil? && current_order.shipping_address.nil?
      new_address = Spree::Address.new address_attributes(amazon_address, spree_user_address)
      new_address.save!

      current_order.billing_address = new_address
      current_order.shipping_address = new_address
    else
      current_order.shipping_address.update_attributes(address_attributes(amazon_address, spree_user_address))
    end

    current_order.save!
  end

  def address_attributes(amazon_address, spree_user_address = nil)
    {
      firstname: amazon_address.first_name || spree_user_address.try(:first_name) || "Amazon",
      lastname: amazon_address.last_name || spree_user_address.try(:last_name) || "User",
      address1: amazon_address.address1 || spree_user_address.try(:address1) || "N/A",
      address2: amazon_address.address2 || spree_user_address.try(:address2),
      phone: amazon_address.phone || spree_user_address.try(:phone) || "000-000-0000",
      city: amazon_address.city || spree_user_address.try(:city),
      zipcode: amazon_address.zipcode || spree_user_address.try(:zipcode),
      state: amazon_address.state || spree_user_address.try(:state),
      country: amazon_address.country || spree_user_address.try(:country)
    }
  end

  def check_current_order
    unless current_order
      head :ok
    end
  end

  def check_amazon_reference_id
    unless current_order.amazon_order_reference_id
      head :ok
    end
  end
end
