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
        'us' => "https://static-na.payments-amazon.com/checkout.js",
        'uk' => "https://static-eu.payments-amazon.com/checkout.js",
        'de' => "https://static-eu.payments-amazon.com/checkout.js",
        'jp' => "https://static-fe.payments-amazon.com/checkout.js",
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

    def authorize(amount, amazon_checkout, gateway_options={})
      return ActiveMerchant::Billing::Response.new(true, 'Success', {}) if amount < 0

      load_amazon_pay

      params = {
        chargePermissionId: amazon_checkout.order_reference,
        chargeAmount: {
          amount: (amount / 100.0).to_s,
          currencyCode: gateway_options[:currency]
        },
        captureNow: true,
        canHandlePendingAuthorization: true
      }

      response = AmazonPay::Charge.create(params)

      success = response.code.to_i == 200 || response.code.to_i == 201
      message = 'Success'
      soft_decline = false

      unless success
        body = JSON.parse(response.body, symbolize_names: true)
        message = body[:message]
        soft_decline = body[:reasonCode] == 'SoftDeclined'
      end

      # Saving information in last amazon transaction for error flow in amazon controller
      amazon_checkout.update!(
        success: success,
        message: message,
        capture_id: body[:chargeId],
        soft_decline: soft_decline,
        retry: !success
      )
      ActiveMerchant::Billing::Response.new(success, message, 'response' => response.body)
    end

    def capture(amount, amazon_checkout, gateway_options={})
      return credit(amount.abs, nil, nil, gateway_options) if amount < 0

      load_amazon_pay

      params = {
        captureAmount: {
          amount: (amount / 100.0).to_s,
          currencyCode: gateway_options[:currency]
        },
        softDescriptor: 'Store Name'
      }

      response = AmazonPay::Charge.capture(amazon_checkout.capture_id, params)

      success = response.code.to_i == 200 || response.code.to_i == 201
      message = 'Success'
      soft_decline = false

      unless success
        body = JSON.parse(response.body, symbolize_names: true)
        message = body[:message]
        soft_decline = body[:reasonCode] == 'SoftDeclined'
      end

      # Saving information in last amazon transaction for error flow in amazon controller
      amazon_checkout.update!(
        success: success,
        message: message,
        soft_decline: soft_decline,
        retry: !success
      )

      ActiveMerchant::Billing::Response.new(success, message, 'response' => response.body)
    end

    def purchase(amount, amazon_checkout, gateway_options={})
      #auth_result = authorize(amount, amazon_checkout, gateway_options)
      #if auth_result.success?
        capture(amount, amazon_checkout, gateway_options)
      #else
      #  auth_result
      #end
    end

    def credit(amount, _response_code, gateway_options = {})
      payment = gateway_options[:originator].payment
      amazon_transaction = payment.source

      load_amazon_mws(amazon_transaction.order_reference)
      mws_res = @mws.refund(
        amazon_transaction.capture_id,
        operation_unique_id(payment),
        amount / 100.00,
        payment.currency
      )

      response = SpreeAmazon::Response::Refund.new(mws_res)
      ActiveMerchant::Billing::Response.new(true, "Success", response.parse, authorization: response.response_id)
    end

    def void(response_code, gateway_options)
      order = Spree::Order.find_by(:number => gateway_options[:order_id].split("-")[0])
      load_amazon_mws(order.amazon_order_reference_id)
      capture_id = order.amazon_transaction.capture_id

      if capture_id.nil?
        response = @mws.cancel
      else
        response = @mws.refund(capture_id, gateway_options[:order_id], order.order_total_after_store_credit, order.currency)
      end

      ActiveMerchant::Billing::Response.new(true, "Success", Hash.from_xml(response.body))
    end

    def cancel(response_code)
      payment = Spree::Payment.find_by!(response_code: response_code)
      order = payment.order
      load_amazon_mws(payment.source.order_reference)
      capture_id = order.amazon_transaction.capture_id

      if capture_id.nil?
        response = @mws.cancel
      else
        response = @mws.refund(capture_id, order.number, payment.credit_allowed, payment.currency)
      end

      ActiveMerchant::Billing::Response.new(true, "#{order.number}-cancel", Hash.from_xml(response.body))
    end

    private

    def load_amazon_pay
      AmazonPay.region = preferred_region
      AmazonPay.public_key_id = preferred_public_key_id
      AmazonPay.sandbox = preferred_test_mode
      AmazonPay.private_key = preferred_private_key_file_location
    end

    def extract_order_and_payment_number(gateway_options)
      gateway_options[:order_id].split('-', 2)
    end

    # Amazon requires unique ids. Calling with the same id multiple times means
    # the result of the previous call will be returned again. This can be good
    # for things like asynchronous retries, but would break things like multiple
    # captures on a single authorization.
    def operation_unique_id(payment)
      "#{payment.number}-#{random_suffix}"
    end

    # A random string of lowercase alphanumeric characters (i.e. "base 36")
    def random_suffix
      length = 10
      SecureRandom.random_number(36 ** length).to_s(36).rjust(length, '0')
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
