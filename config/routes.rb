##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
Spree::Core::Engine.routes.draw do
  resource :amazon_order, only: [], controller: "amazon" do
    member do
      get 'address'
      post 'payment'
      get 'delivery'
      post 'confirm'
      post 'complete'
      get 'complete'
    end
  end

  namespace :api, defaults: { format: 'json' } do
    namespace :v2 do
      namespace :storefront do
        resource :amazon_order, only: [], controller: 'amazon' do
          member do
            post 'payment'
            post 'address'
            post 'confirm'
            post 'complete'
          end
        end
      end
    end
  end


  post 'amazon_callback', to: 'amazon_callback#new'
  get 'amazon_callback', to: 'amazon_callback#new'
end
