class EpdsController < ApplicationController
    skip_before_action :verify_authenticity_token
    
    include ApplicationHelper
    include StoresHelper

    require 'uri'
    require 'barby'
    require 'barby/barcode'
    require 'barby/barcode/qr_code'
    require 'barby/outputter/png_outputter'

    def generate
        id = params[:id]
        @store = Store.find(id)

        epd_url = EPD_HOST + '/create'
        response_nil = false
        begin
            response = HTTParty.post(epd_url, 
                headers: { 'Content-Type' => 'application/json' },
                body: @store.item.to_json )
        rescue => ex
            response_nil = true
        end
        if response_nil || response.code != 200
            render json: {"error": "cannot generate EPD"},
                   status: 500
            return
        end

        retVal = write_item(response, {}, "zkEPD", nil, nil)
        retVal = write_item({date: nil, volume: nil, epd: response}, {}, "ConcreteDPP", nil, nil)

        render plain: '',
               status: 200
    end

    def publish
        my_id = params[:id]

        item = {"id": my_id}
        @store = Store.new
        preauth_code = SecureRandom.urlsafe_base64(17)[0,22]
        item["preauth-code"] = preauth_code
        @store.item = item
        @store.key = preauth_code
        @store.save

        payload = {
            "grants": {
                "urn:ietf:params:oauth:grant-type:pre-authorized_code": {
                    "pre-authorized_code": preauth_code,
                    "user_pin_required": false
                }
            },
            "credentials": [
                CREDENTIAL_TYPE
            ],
            "credential_issuer": ISSUER_HOST + CREDENTIAL_PATH
        }
        @credential_offer = "openid-credential-offer://?credential_offer=" + 
                                URI.encode_www_form_component(payload.to_json)
        @id = preauth_code

    end

    def dpp
        @store = Store.find_by_key(params[:id]) rescue nil?
        if @store.nil?
            render json: {"error": "id not found"},
                   status: 200
        else
            # since VC/VP does not work yet, just build it on our own
            # credential = @store.item["credential"]
            # payload = JWT.decode(@store.item["credential"], nil, false)
            content = @store.item["epd-data"]
            options = {}
            options[:issuer] = ENV['ISSUER_DID']
            options[:issuer_privateKey] = Oydid.generate_private_key(ENV['ISSUER_PWD'].to_s, 'ed25519-priv', {}).first
            options[:holder] = ENV['HOLDER_DID']
            vc, msg = Oydid.create_vc(content, options)

            options[:holder_privateKey] = Oydid.generate_private_key(ENV['HOLDER_PWD'].to_s, 'ed25519-priv', {}).first
            vp, msg = Oydid.create_vp(JSON.parse(vc.to_json), options)

            options[:location] = DISP_HOST
            retVal, msg = Oydid.publish_vp(vp, options)
            content = {
                service: [
                    id: "#product",
                    type: "ProductPassport",
                    serviceEndpoint: retVal
                ]
            }
            @rec = Store.find(@store.item["id"])
            item = @rec.item
            item["vp"] = retVal.to_s
            retVal, msg = Oydid.create(content,{})
            item["did"] = retVal["did"].to_s
            @rec.item = item
            @rec.save
            render json: {did: retVal["did"]},
                   status: 200
        end
    end

end