module AmazonPay
  class Charge
    def self.create(params)
      response = AmazonPay.request('post', 'charges', params)
      response.body
    end

    def self.get(charge_id)
      response = AmazonPay.request('get', "charges/#{charge_id}")
      response.body
    end

    def self.capture(charge_id, params)
      response = AmazonPay.request('post', "charges/#{charge_id}", params)
      response.body
    end

    def self.cancel(charge_id, params)
      response = AmazonPay.request('delete', "charges/#{charge_id}/cancel", params)
      response.body
    end
  end
end
