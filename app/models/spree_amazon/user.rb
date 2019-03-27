module SpreeAmazon
  class User
    class << self
        def find(gateway:, access_token: nil)
          response = lwa(gateway).get_login_profile(access_token)
          from_response(response)
        end

        def from_response(response)
          return nil if response['email'].blank?
          attributes_from_response(response)
        end

      private

        def lwa(gateway)
          AmazonPay::Login.new(gateway.preferred_client_id,
                               region: :na, # Default: :na
                               sandbox: gateway.preferred_test_mode) # Default: false
        end

        def attributes_from_response(response)
          {
            'provider' => 'amazon',
            'info' => {
              'email' => response['email'],
              'name' => response['name']
            },
            'uid' => response['user_id']
          }
        end
      end
  end
end
