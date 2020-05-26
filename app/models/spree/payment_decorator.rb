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
  self.scope :amazon, -> { where(source_type: 'Spree::AmazonTransaction') }
end

::Spree::Payment.prepend(Spree::PaymentDecorator)