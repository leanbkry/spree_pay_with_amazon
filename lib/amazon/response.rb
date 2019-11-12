module AmazonPay
  class Response
    attr_reader :type, :response, :body

    def initialize(response)
      @type = self.class.name.demodulize
      @response = response
      @body = JSON.parse(response.body, symbolize_names: true)
    end

    def success?
      response_code == 200 || response_code == 201
    end

    def response_code
      response.code.to_i
    end

    def reason_code
      return nil if success?
      body[:reasonCode]
    end

    def soft_decline?
      return nil if success?
      reason_code == 'SoftDeclined'
    end

    def message
      return 'Success' if success?
      body[:message]
    end
  end
end
