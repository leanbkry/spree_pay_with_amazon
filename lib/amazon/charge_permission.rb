module AmazonPay
  class ChargePermission
    def self.get(charge_permission_id)
      response = AmazonPay.request('get', "chargePermissions/#{charge_permission_id}")
      response.body
    end

    def self.update(charge_permission_id, params)
      response = AmazonPay.request('patch', "chargePermissions/#{charge_permission_id}", params)
      response.body
    end

    def self.close(charge_permission_id, params)
      response = AmazonPay.request('delete', "chargePermissions/#{charge_permission_id}/close", params)
      response.body
    end
  end
end
