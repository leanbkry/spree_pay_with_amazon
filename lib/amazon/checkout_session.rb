module AmazonPay
  class CheckoutSession
    def self.create(params)
      response = AmazonPay.request('post', 'checkoutSessions', params)
      response.body
    end

    def self.get(checkout_session_id)
      response = AmazonPay.request('get', "checkoutSessions/#{checkout_session_id}")
      JSON.parse(response.body, symbolize_names: true)
    end

    def self.update(checkout_session_id, params)
      response = AmazonPay.request('patch', "checkoutSessions/#{checkout_session_id}", params)
      JSON.parse(response.body, symbolize_names: true)
    end
  end
end
