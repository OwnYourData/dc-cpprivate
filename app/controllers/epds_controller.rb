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
        @fix_store = Store.find(1) # !!!fix-me
        meta = @fix_store.meta
        if meta.is_a?(String)
            meta = JSON.parse(meta) rescue {}
        end
        if !meta.is_a?(Hash)
            meta = {}
        end
        response_nil = false

        if meta["async-id"].nil?
            epd_url = EPD_HOST + '/creation?snark=true'
            begin
                response = HTTParty.post(epd_url, 
                    headers: { 'Content-Type' => 'application/json' },
                    body: @store.item.to_json )
            rescue => ex
                response_nil = true
            end
        else
            epd_url = EPD_HOST + '/creation/' + meta["async-id"].to_s
            begin
                response = HTTParty.get(epd_url)
            rescue => ex
                response_nil = true
            end
        end
        if response_nil || response.code != 200
            if response.code == 202
                @fix_store = Store.find(1)
                meta = @fix_store.meta
                if meta.nil?
                    meta = {}
                end
                meta["async-id"] = response["id"].to_s
                @fix_store.meta = meta
                @fix_store.save
                render json: {"error": "ZKP generation started, click 'Generate EPD' again to get status updates."},
                       status: 500
            else
                render json: {"error": "cannot generate EPD"},
                       status: 500
            end
            return
        end
        if response["state"] == "Complete"
            response_nil = false
            epd_url = EPD_HOST + '/creation/' + meta["async-id"].to_s + '/result'
            begin
                response = HTTParty.get(epd_url)
            rescue => ex
                response_nil = true
            end
            if response_nil || response.code != 200
                render json: {"error": "cannot generate EPD"},
                       status: 500
                return
            end

            @fix_store.meta = {}
            @fix_store.save

            retVal = write_item(response, {}, "zkEPD", nil, nil)
            retVal = write_item({date: nil, volume: nil, epd: response}, {}, "ConcreteDPP", nil, nil)

            render plain: '',
                   status: 200
        elsif response["state"] == "Inprogress"
            render json: {"error": "ZKP generation in progress, click 'Generate EPD' again to get status updates."},
                   status: 500
        else
            render json: {"error": "cannot generate EPD"},
                   status: 500
        end

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

    def dpp_button
        @store = Store.find(params[:id]) rescue nil?
        if @store.nil?
            render json: {"error": "id not found"},
                   status: 404
        else
            # since VC/VP does not work yet, just build it on our own
            # credential = @store.item["credential"]
            # payload = JWT.decode(@store.item["credential"], nil, false)
            content = @store.item.slice("epd", "date", "volume")
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
                service: [{
                    id: "#product",
                    type: "ProductPassport",
                    serviceEndpoint: retVal
                }, {
                    id: "#info",
                    type: "EPD",
                    data: {
                        description: @store.item["epd"]["description"],
                        gwp: @store.item["epd"]["A13_gwp"],
                        date: @store.item["date"],
                        volume: @store.item["volume"]
                    }
                }]
            }
            item = @store.item
            item["vp"] = retVal.to_s
            retVal, msg = Oydid.create(content,{})
            item["did"] = retVal["did"].to_s
            @store.item = item
            @store.save
            render json: {did: retVal["did"]},
                   status: 200
        end
    end

    def issue
        @item_id = params[:id]
        @store = Store.find(params[:id]) rescue nil
        if @store.nil?
            redirect_to '/'
            return
        end

        item = {"id": @store.id, "type": DELIVERY_VC}
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
            "credential_configuration_ids": [
                DELIVERY_VC
            ],
            "credential_issuer": ISSUER_HOST + CREDENTIAL_PATH
        }
        @credential_offer = "openid-credential-offer://?credential_offer=" + 
                                URI.encode_www_form_component(payload.to_json)
        @id = preauth_code.to_s
    end

    def send_vc
        puts params.to_json
        id = params["id"]
        @store = Store.find(id) rescue nil
        if @store.nil?
            @error_msg = "Unknonw ID '#{id}'"
            respond_to do |format|
                format.js { render 'error_vc' }
            end
            return
        end

        # create VC
        content = @store.item
        if content.is_a?(String)
            content = JSON.parse(content) rescue {}
        end
        options = {}
        options[:issuer] = ENV['ISSUER_DID']
        options[:issuer_privateKey] = Oydid.generate_private_key(ENV['ISSUER_PWD'].to_s, 'ed25519-priv', {}).first
        options[:holder] = @store.item["holder"]
        vc, msg = Oydid.create_vc(content, options)

        success = false
        if msg.to_s == ""
            # send to Online Wallet
            wallet_url = params["holder"]
            if !wallet_url.start_with?("http")
                wallet_url = "https://" + wallet_url
            end
            if wallet_url == "https://sm-private.data-container.net"
                auth_url = wallet_url + "/oauth/token"   
                app_key = ENV["SM_APPKEY"]
                app_secret = ENV["SM_APPSECRET"]
                rensponse_nil = false
                begin
                    response = HTTParty.post(auth_url, 
                        headers: { 'Content-Type' => 'application/json' },
                        body: { client_id: app_key, 
                                client_secret: app_secret, 
                                grant_type: "client_credentials" }.to_json )
                rescue => ex
                  response_nil = true
                end
                if !response_nil
                    token = response.parsed_response["access_token"].to_s rescue ""
                    wallet_headers = { 
                      'Accept' => '*/*',
                      'Content-Type' => 'application/json',
                      'Authorization' => 'Bearer ' + token
                    }
                    begin
                        response = HTTParty.post(wallet_url + "/api/data", 
                                      headers: wallet_headers, 
                                      body: { data: vc, 
                                              meta: {schema: 'ReceivedConcreteDeliveryVCs'}}.to_json )
                    rescue => ex
                      response_nil = true
                    end
                    if !response_nil
                        success = true
                    end
                end
            else
                @error_msg = "unsupported wallet"
                respond_to do |format|
                    format.js { render 'error_vc' }
                end
                return
            end

            if success
                respond_to do |format|
                    format.js { render 'send_vc' }
                end
            else
                @error_msg = "Could not send Verifiable Credential"
                respond_to do |format|
                    format.js { render 'error_vc' }
                end
            end                
        else
            @error_msg = msg
            respond_to do |format|
                format.js { render 'error_vc' }
            end
        end            

    end

end