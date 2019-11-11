##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
module Spree
  class Gateway::Amazon < Gateway
    REGIONS = %w[us uk de jp].freeze

    preference :currency, :string, default: -> { Spree::Config.currency }
    preference :client_id, :string
    preference :merchant_id, :string
    preference :aws_access_key_id, :string
    preference :aws_secret_access_key, :string
    preference :region, :string, default: 'us'
    preference :site_domain, :string
    preference :public_key_id, :string
    preference :private_key_file_location, :string

    has_one :provider

    validates :preferred_region, inclusion: { in: REGIONS }

    def self.for_currency(currency)
      where(active: true).detect { |gateway| gateway.preferred_currency == currency }
    end

    def widgets_url
      {
        'us' => 'https://static-na.payments-amazon.com/checkout.js',
        'uk' => 'https://static-eu.payments-amazon.com/checkout.js',
        'de' => 'https://static-eu.payments-amazon.com/checkout.js',
        'jp' => 'https://static-fe.payments-amazon.com/checkout.js'
      }.fetch(preferred_region)
    end

    def supports?(source)
      true
    end

    def method_type
      'amazon'
    end

    def provider_class
      AmazonTransaction
    end

    def payment_source_class
      AmazonTransaction
    end

    def source_required?
      true
    end

    def authorize(amount, amazon_transaction, gateway_options={})
      return ActiveMerchant::Billing::Response.new(true, 'Success', {}) if amount < 0

      load_amazon_pay

      params = {
        chargePermissionId: amazon_transaction.order_reference,
        chargeAmount: {
          amount: (amount / 100.0).to_s,
          currencyCode: gateway_options[:currency]
        },
        captureNow: true,
        canHandlePendingAuthorization: true
      }

      response = AmazonPay::Charge.create(params)

      success = response.code.to_i == 200 || response.code.to_i == 201
      body = JSON.parse(response.body, symbolize_names: true)
      message = 'Success'
      soft_decline = false

      unless success
        message = body[:message]
        soft_decline = body[:reasonCode] == 'SoftDeclined'
      end

      # Saving information in last amazon transaction for error flow in amazon controller
      amazon_transaction.update!(
        success: success,
        message: message,
        capture_id: body[:chargeId],
        soft_decline: soft_decline,
        retry: !success
      )
      ActiveMerchant::Billing::Response.new(success, message, 'response' => response.body)
    end

    def capture(amount, response_code, gateway_options={})
      return credit(amount.abs, response_code, gateway_options) if amount < 0

      payment = Spree::Payment.find_by!(response_code: response_code)
      amazon_transaction = payment.source

      load_amazon_pay

      params = {
        captureAmount: {
          amount: (amount / 100.0).to_s,
          currencyCode: gateway_options[:currency]
        },
        softDescriptor: Spree::Store.current.name
      }

      capture_id = update_for_backwards_compatibility(amazon_transaction.capture_id)

      response = AmazonPay::Charge.capture(capture_id, params)

      success = response.code.to_i == 200 || response.code.to_i == 201
      message = 'Success'
      soft_decline = false

      unless success
        body = JSON.parse(response.body, symbolize_names: true)
        message = body[:message]
        soft_decline = body[:reasonCode] == 'SoftDeclined'
      end

      # Saving information in last amazon transaction for error flow in amazon controller
      amazon_transaction.update!(
        success: success,
        message: message,
        soft_decline: soft_decline,
        retry: !success
      )

      ActiveMerchant::Billing::Response.new(success, message)
    end

    def purchase(amount, amazon_checkout, gateway_options = {})
      capture(amount, amazon_checkout.capture_id, gateway_options)
    end

    def credit(amount, response_code, _gateway_options = {})
      payment = Spree::Payment.find_by!(response_code: response_code)
      amazon_transaction = payment.source

      load_amazon_pay

      capture_id = update_for_backwards_compatibility(amazon_transaction.capture_id)

      params = {
        chargeId: capture_id,
        refundAmount: {
          amount: (amount / 100.0).to_s,
          currencyCode: payment.currency
        },
        softDescriptor: Spree::Store.current.name
      }

      response = AmazonPay::Refund.create(params)

      success = response.code.to_i == 200 || response.code.to_i == 201
      body = JSON.parse(response.body, symbolize_names: true)
      message = 'Success'

      unless success
        message = body[:message]
      end

      ActiveMerchant::Billing::Response.new(success, message,
                                            authorization: body[:refundId])
    end

    def void(response_code, gateway_options = {})
      cancel(response_code || extract_order_and_payment_number(gateway_options[:order_id]).second)
    end

    def cancel(response_code)
      payment = Spree::Payment.find_by!(response_code: response_code)
      amazon_transaction = payment.source

      if amazon_transaction.capture_id.nil?

        params = {
          cancellationReason: 'Cancelled Order'
        }

        response = AmazonPay::Charge.cancel(amazon_transaction.order_reference, params)

        success = response.code.to_i == 200 || response.code.to_i == 201
        body = JSON.parse(response.body, symbolize_names: true)
        message = 'Success'

        unless success
          message = body[:message]
        end

        ActiveMerchant::Billing::Response.new(success, message)
      else
        credit(payment.credit_allowed * 100, response_code)
      end
    end

    private

    def load_amazon_pay
      AmazonPay.region = preferred_region
      AmazonPay.public_key_id = preferred_public_key_id
      AmazonPay.sandbox = preferred_test_mode
      AmazonPay.private_key = preferred_private_key_file_location
    end

    def update_for_backwards_compatibility(capture_id)
      if capture_id[20] == 'A'
        capture_id[20, 1] = 'C'
      else
        capture_id
      end
    end

    # Allows simulating errors in sandbox mode if the *last* name of the
    # shipping address is "SandboxSimulation" and the *first* name is one of:
    #
    #   InvalidPaymentMethodHard-<minutes> (-<minutes> is optional. between 1-240.)
    #   InvalidPaymentMethodSoft-<minutes> (-<minutes> is optional. between 1-240.)
    #   AmazonRejected
    #   TransactionTimedOut
    #   ExpiredUnused-<minutes> (-<minutes> is optional. between 1-60.)
    #   AmazonClosed
    #
    # E.g. a full name like: "AmazonRejected SandboxSimulation"
    #
    # See https://payments.amazon.com/documentation/lpwa/201956480 for more
    # details on Amazon Payments Sandbox Simulations.
    def sandbox_authorize_simulation_string(order)
      return nil if !preferred_test_mode
      return nil if order.ship_address.nil?
      return nil if order.ship_address.lastname != 'SandboxSimulation'

      reason, minutes = order.ship_address.firstname.to_s.split('-', 2)
      # minutes is optional and is only used for some of the reason codes
      minutes ||= '1'

      case reason
      when 'InvalidPaymentMethodHard' then %({"SandboxSimulation": {"State":"Declined", "ReasonCode":"InvalidPaymentMethod", "PaymentMethodUpdateTimeInMins":#{minutes}}})
      when 'InvalidPaymentMethodSoft' then %({"SandboxSimulation": {"State":"Declined", "ReasonCode":"InvalidPayment Method", "PaymentMethodUpdateTimeInMins":#{minutes}, "SoftDecline":"true"}})
      when 'AmazonRejected'           then  '{"SandboxSimulation": {"State":"Declined", "ReasonCode":"AmazonRejected"}}'
      when 'TransactionTimedOut'      then  '{"SandboxSimulation": {"State":"Declined", "ReasonCode":"TransactionTimedOut"}}'
      when 'ExpiredUnused'            then %({"SandboxSimulation": {"State":"Closed", "ReasonCode":"ExpiredUnused", "ExpirationTimeInMins":#{minutes}}})
      when 'AmazonClosed'             then  '{"SandboxSimulation": {"State":"Closed", "ReasonCode":"AmazonClosed"}}'
      else
        Rails.logger.error('"SandboxSimulation" was given as the shipping first name but the last name was not a valid reason code: ' + order.ship_address.firstname.inspect)
        nil
      end
    end
  end
end
