{renderable} = require 'acoustic-line'

module.exports = renderable (o) ->
  {profile,settings,param} = require 'acoustic-line'
  profile name:"voicemail-#{o.name}", ->
    settings ->
      param name:'user-agent-string', value:"#{pkg.name} #{pkg.version} #{o.name} #{o.sip_port}"
      param name:'username', value:"#{pkg.name}-#{o.name}"
      param name:'debug', value:2
      param name:'sip-trace', value:false

      param name:'sip-port', value:o.sip_port
      param name:'bind-params', value:'transport=udp,tcp'

      param name:'sip-ip', value:'0.0.0.0'
      param name:'ext-sip-ip', value:o.local_ip

      param name:'rtp-ip', value:'0.0.0.0'
      param name:'ext-rtp-ip', value:o.local_ip

      param name:'apply-inbound-acl', value:'default'

      param name:'dialplan', value:'XML'
      param name:'context', value:o.context
      param name:'auth-calls', value:'false'
      param name:'auth-all-packets', value:'false'
      param name:'accept-blind-reg', value:'true'
      param name:'accept-blind-auth', value:'true'
      param name:'sip-options-respond-503-on-busy', value:'false'
      param name:'pass-callee-id', value:'false'
      param name:'caller-id-type', value:'pid'

      param name:'manage-presence', value:'false'
      param name:'manage-shared-appearance', value:'false'

      param name:'enable-soa', value:'true'
      param name:'inbound-codec-negotiation', value:'scrooge'
      param name:'inbound-late-negotiation', value:'true'

      param name:'inbound-codec-prefs', value:'PCMA,PCMU'
      param name:'outbound-codec-prefs', value:'PCMA,PCMU'
      param name:'renegotiate-codec-on-reinvite', value:'true'
      param name:'inbound-bypass-media', value:'false'
      param name:'inbound-proxy-media', value:'false'
      param name:'media-option', value:'bypass-media-after-att-xfer'

      param name:'inbound-zrtp-passthru', value:'false'
      param name:'disable-transcoding', value:'true'

      param name:'inbound-use-callid-as-uuid', value:'true'

      param name:'dtmf-type', value:'rfc2833'
      param name:'dtmf-duration', value:'200'
      param name:'rfc2833-pt', value:'101'
      param name:'use-rtp-timer', value:'true'
      param name:'rtp-timer-name', value:'soft'
      param name:'pass-rfc2833', value:'true'

      param name:'max-proceeding', value:'2000'

      param name:'nonce-ttl', value:'60'

      param name:'NDLB-received-in-nat-reg-contact', value:'false'
      param name:'nat-options-ping', value:'false'
      param name:'all-reg-options-ping', value:'false'
      param name:'aggressive-nat-detection', value:'false'

      param name:'rtp-timeout-sec', value:'300'
      param name:'rtp-hold-timeout-sec', value:'1800'

      param name:'disable-transfer', value:'true'
      param name:'disable-register', value:'true'
      param name:'enable-3pcc', value:'false'
      param name:'stun-enabled', value:'false'
      param name:'stun-auto-disable', value:'true'

      param name:'timer-T1', value:o.timer_t1
      param name:'timer-T1X64', value:o.timer_t1x64
      param name:'timer-T2', value:o.timer_t2
      param name:'timer-T4', value:o.timer_t4
