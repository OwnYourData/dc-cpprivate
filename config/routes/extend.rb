scope '/' do
    match 'api/epd/generate/:id', to: 'epds#generate',   via: 'post'
    # match 'api/epd/validate/:id', to: 'epds#validate',   via: 'post'
    match 'api/dpp/generate/:id', to: 'epds#dpp_button', via: 'post'

    # signing with wallet (issue vc)
    match '/publish/:id',                              to: 'epds#publish',         via: 'get'
    match '/oyd/.well-known/openid-credential-issuer', to: 'oid4vci#oyd',          via: 'get'
    match '/oyd/token',                                to: 'oid4vci#token',        via: 'post'
    match '/oyd/credentials',                          to: 'oid4vci#credentials',  via: 'post'
    match '/oyd/notification',                         to: 'oid4vci#notification', via: 'post'
    match '/dpp',                                      to: 'epds#dpp',             via: 'get'

    # validation of DPP
    match '/validate/:id', to: 'epds#validate', via: 'get'

    # issuing a VC
    match '/issue/:id',    to: 'epds#issue',    via: 'get'
    match '/send_vc',      to: 'epds#send_vc',  via: 'post'

end
