##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
module Spree::PaymentDecorator
  def self.prepended(base)
    base.scope :amazon, -> { where(source_type: 'Spree::AmazonTransaction') }
  end
end

::Spree::Payment.prepend(Spree::PaymentDecorator)