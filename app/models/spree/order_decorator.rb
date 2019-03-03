##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
Spree::Order.class_eval do
  has_many :amazon_transactions

  def amazon_transaction
    amazon_transactions.last
  end

  def amazon_order_reference_id
    amazon_transaction.try(:order_reference)
  end

  def confirmation_required?
    Spree::Config[:always_include_confirm_step] ||
      payments.valid.map(&:payment_method).compact.any?(&:payment_profiles_supported?) ||
      payments.valid.map(&:payment_method).compact.any? { |pm| pm.is_a? Spree::Gateway::Amazon } ||
      # Little hacky fix for #4117
      # If this wasn't here, order would transition to address state on confirm failure
      # because there would be no valid payments any more.
      confirm?
  end

  def assign_default_credit_card
    return if payments.valid.amazon.count > 0
    if payments.from_credit_card.size == 0 && user_has_valid_default_card? && payment_required?
      cc = user.default_credit_card
      payments.create!(payment_method_id: cc.payment_method_id, source: cc, amount: total)
    end
  end
end