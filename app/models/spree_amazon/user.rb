module SpreeAmazon
  class User
    class << self
      def from_response(response)
        new attributes_from_response(response[:buyer])
      end

      private

      def attributes_from_response(buyer_params)
        {
          name: buyer_params[:name],
          email: buyer_params[:email],
          uid: buyer_params[:buyerId]
        }
      end
    end

    attr_accessor :email, :name, :uid

    def initialize(attributes)
      attributes.each_pair do |key, value|
        send("#{key}=", value)
      end
    end

    def auth_hash
      {
        'provider' => 'amazon',
        'info' => {
          'email' => email,
          'name' => name
        },
        'uid' => uid
      }
    end
  end
end
