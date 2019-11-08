module AmazonPay
  class Refund
    def self.create(params)
      response = AmazonPay.request('post', 'refunds', params)
      response.body
    end

    def self.get(refund_id)
      response = AmazonPay.request('get', "refunds/#{refund_id}")
      response.body
    end
  end
end
