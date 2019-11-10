##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
class Spree::AmazonpayController < Spree::StoreController
  helper 'spree/orders'
  before_action :check_current_order
  before_action :gateway, only: [:confirm, :create, :payment, :complete]
  skip_before_action :verify_authenticity_token, only: %i[create complete]

  respond_to :json

  def create
    if current_order.cart?
      current_order.next!
    else
      current_order.state = 'address'
      current_order.save!
    end

    params = { webCheckoutDetail:
              { checkoutReviewReturnUrl: 'http://localhost:3000/amazonpay/confirm' },
               storeId: @gateway.preferred_client_id }

    render json: AmazonPay::CheckoutSession.create(params)
  end

  def confirm
    redirect_to cart_path && return unless current_order.address?

    response = AmazonPay::CheckoutSession.get(amazon_checkout_session_id)

    amazon_user = SpreeAmazon::User.from_response(response)
    set_user_information(amazon_user.auth_hash)

    amazon_address = SpreeAmazon::Address.from_response(response)
    address_attributes = amazon_address.attributes

    if spree_address_book_available?
      address_attributes = address_attributes.merge(user: spree_current_user)
    end

    current_order.update_attributes!(bill_address_attributes: address_attributes,
                                     ship_address_attributes: address_attributes,
                                     email: amazon_user.email)

    current_order.next!

    if current_order.shipments.empty?
      redirect_to cart_path, notice: 'Cannot ship to this address'
    end
  end

  def payment
    authorize!(:edit, current_order, cookies.signed[:guest_token])

    params = {
      webCheckoutDetail: {
        checkoutResultReturnUrl: 'http://localhost:3000/amazonpay/complete'
      },
      paymentDetail: {
        paymentIntent: 'Authorize',
        canHandlePendingAuthorization: true,
        chargeAmount: {
          amount: current_order.order_total_after_store_credit,
          currencyCode: current_currency
        }
      },
      merchantMetadata: {
        merchantReferenceId: current_order.number,
        merchantStoreName: current_store.name,
        noteToBuyer: '',
        customInformation: ''
      }
    }

    response = AmazonPay::CheckoutSession.update(amazon_checkout_session_id, params)
    redirect_to response[:webCheckoutDetail][:amazonPayRedirectUrl]
  end

  def complete
    response = AmazonPay::CheckoutSession.get(amazon_checkout_session_id)

    @order = current_order

    payments = @order.payments
    payment = payments.create
    payment.payment_method = @gateway
    payment.source ||= Spree::AmazonTransaction.create(
      order_reference: response[:chargePermissionId],
      order_id: @order.id,
      capture_id: response[:chargeId],
      retry: false
    )
    payment.amount = @order.order_total_after_store_credit
    payment.response_code = response[:chargeId]
    payment.save!

    @order.reload

    while @order.next; end

    if @order.complete?
      @current_order = nil
      flash.notice = Spree.t(:order_processed_successfully)
      flash[:order_completed] = true
      redirect_to spree.order_path(@order)
    else
      amazon_transaction = @order.amazon_transaction
      amazon_transaction.reload
      if amazon_transaction.soft_decline
        redirect_to confirm_amazonpay_path(amazonCheckoutSessionId: amazon_checkout_session_id), notice: amazon_transaction.message
      else
        @order.amazon_transactions.destroy_all
        @order.save!
        redirect_to cart_path, notice: Spree.t(:order_processed_unsuccessfully)
      end
    end
  end

  def gateway
    @gateway ||= Spree::Gateway::Amazon.for_currency(current_order.currency)
    AmazonPay.region = @gateway.preferred_region
    AmazonPay.public_key_id = @gateway.preferred_public_key_id
    AmazonPay.sandbox = @gateway.preferred_test_mode
    AmazonPay.private_key = @gateway.preferred_private_key_file_location
  end

  private

  def amazon_checkout_session_id
    params[:amazonCheckoutSessionId]
  end

  def set_user_information(auth_hash)
    return unless Gem::Specification.find_all_by_name('spree_social').any? && auth_hash

    authentication = Spree::UserAuthentication.find_by_provider_and_uid(auth_hash['provider'], auth_hash['uid'])

    if authentication.present? && authentication.try(:user).present?
      user = authentication.user
      sign_in(user, scope: :spree_user)
    elsif spree_current_user
      spree_current_user.apply_omniauth(auth_hash)
      spree_current_user.save!
      user = spree_current_user
    else
      email = auth_hash['info']['email']
      user = Spree::User.find_by_email(email) || Spree::User.new
      user.apply_omniauth(auth_hash)
      user.save!
      sign_in(user, scope: :spree_user)
    end

    # make sure to merge the current order with signed in user previous cart
    set_current_order

    current_order.associate_user!(user)
    session[:guest_token] = nil
  end

  def check_current_order
    unless current_order
      redirect_to cart_path
    end
  end

  def spree_address_book_available?
    Gem::Specification.find_all_by_name('spree_address_book').any?
  end
end
