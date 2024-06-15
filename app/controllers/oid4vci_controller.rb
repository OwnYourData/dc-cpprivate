class Oid4vciController < ApplicationController
    protect_from_forgery with: :null_session
    include ApplicationHelper

    def oyd
        retVal = {
            "credential_issuer": ISSUER_HOST + CREDENTIAL_PATH,
            "credential_endpoint": ISSUER_HOST + CREDENTIAL_PATH + "/credentials",
            "token_endpoint": ISSUER_HOST + CREDENTIAL_PATH + "/token",
            "notification_endpoint": ISSUER_HOST + CREDENTIAL_PATH + "/notification",
            "display": [
                {
                    "name": "OwnYourData",
                    "description": "OYD Signing Demo"
                }
            ],
            "credentials_supported": [
                {
                  "display": [
                    {
                        "name": "Signing Demo",
                        "description": "demonstrate signing with Sphereon Wallet",
                        "text_color": "#000000",
                        "background_color": "#FFFFFF",
                        "logo":{
                            "url": "https://www.ownyourdata.eu/wp-content/uploads/2021/01/oyd_logo_transparent.png",
                            "alt_text": "OYD logo"
                        }
                    }
                  ],
                  "id": "OydCredentialJwt",
                  "types": [
                    "VerifiableCredential",
                    CREDENTIAL_TYPE
                  ],
                  "format": "jwt_vc_json",
                  "cryptographic_binding_methods_supported": [
                    "did:oyd"
                  ],
                  "cryptographic_suites_supported": [
                    "EdDSA"
                  ],
                  "credential_subject_issuance": {
                      "subject_proof_mode": "proof_replace",
                      "notification_events_supported": [
                          "credential_deleted_holder_signed"
                      ]
                  }   
                }
            ]
        }

        render json: retVal.to_json,
               status: 200
    end

    def token
        preauth_code = params["pre-authorized_code"].to_s
        @store = Store.find_by_key(preauth_code)
        item = @store.item


        ecdsa_key = OpenSSL::PKey::EC.generate('secp256k1')
        algorithm = "ES256K"
        header_fields = {
            alg: algorithm,
            typ: 'JWT'
        }
        payload = {
            "iat": Time.now.utc.to_i,
            "exp": 300,
            "iss": ISSUER_HOST + CREDENTIAL_PATH,
            "preAuthorizedCode": preauth_code
        }
        access_token = JWT.encode(payload, ecdsa_key, algorithm, header_fields)
        nonce = SecureRandom.alphanumeric(10)
        item["nonce"] = nonce
        @store.item = item
        @store.key = nonce
        @store.save

        retVal = {
            "access_token": access_token,
            "token_type": "bearer",
            "expires_in": 86400,
            "c_nonce": nonce,
            "c_nonce_expires_in": 86400
        }

        render json: retVal,
               status: 200
    end

    def credentials
        proof = params["proof"]
        jwt = proof["jwt"]
        data = JWT.decode(jwt, nil, false)
        nonce = data.first["nonce"]
        notification_id = SecureRandom.alphanumeric(32)
        @store = Store.find_by_key(nonce)
        item = @store.item
        issuer_did = ENV['ISSUER_DID'].to_s
        private_key = RbNaCl::Signatures::Ed25519::SigningKey.new(RbNaCl::Hash.sha256(ENV['ISSUER_PWD']))

        @epd_data = Store.find(item["id"])
        item["epd-data"] = @epd_data.item
        # options = {}
        # options[:issuer] = issuer_did
        # options[:issuer_privateKey] = Oydid.generate_private_key(ENV['ISSUER_PWD'].to_s, 'ed25519-priv', {}).first
        # options[:holder] = issuer_did
        # content, msg = Oydid.create_vc(@epd_data.item, options)
        content = @epd_data.item
        options = {}
        options[:issuer] = issuer_did
        options[:issuer_privateKey] = Oydid.generate_private_key(ENV['ISSUER_PWD'].to_s, 'ed25519-priv', {}).first
        options[:holder] = ""
        vc, msg = Oydid.create_vc(content, options)
        vc["@context"] = ["https://www.w3.org/2018/credentials/v1"]
        vc["type"] = ["VerifiableCredential", CREDENTIAL_TYPE]
        expirationDate = Time.now.utc + 3.months
        vc["expirationDate"] = expirationDate.strftime("%Y-%m-%dT%H:%M:%SZ")

        algorithm = 'EdDSA'
        header_fields = {
            alg: algorithm,
            kid: issuer_did + '#key-doc',
            typ: 'JWT'
        }
        payload = vc.dup
        payload["vc"] = vc.dup
        payload["issuer"] = issuer_did
        payload["issuanceDate"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        payload["sub"] = ""
        payload["nbf"] = Time.now.to_i
        payload["exp"] = expirationDate.to_i
        payload["iss"] = issuer_did

puts "------------------"
puts JSON.pretty_generate(payload)
puts "=================="

        retVal ={
          "format": "ldp_vc",
          "credential": JWT.encode(payload, private_key, algorithm, header_fields),
          "c_nonce": nonce,
          "c_nonce_expires_in": 86400,
          "notification_id": notification_id,
          "credential_subject_issuance": {
              "subject_proof_mode": "proof_replace",
              "notification_events_supported": [
                  "credential_deleted_holder_signed"
              ]
          }
        }

        item["notification_id"] = notification_id
        @store.item = item
        @store.key = notification_id
        @store.save

        render json: retVal,
               status: 200
    end

    def notification
        puts "--------------"
        puts params.to_json
        puts "=============="
        notification_id = params["notification_id"]
        @store = Store.find_by_key(notification_id)
        if !@store.nil?
            item = @store.item
            item["credential"] = params["credential"]
            @store.item = item
            @store.key = item["preauth-code"]
            @store.save
        end
        render json: {},
               status: 200
    end

end