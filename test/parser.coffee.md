This format is probably incorrect per section 3.1.2 of RFC3265 (the RURI or Event `id` field should uniquely identify the resource).

    _test = ->
      test_msg1 = '''
        SUBSCRIBE sip:test.phone.kwaoo.net SIP/2.0
        X-CCNQ3-Endpoint: 0972222713@a.phone.kwaoo.net
        Via: SIP/2.0/UDP 192.168.1.106:5063;branch=z9hG4bK-5e721c6;rport
        From: <sip:0972222713@test.phone.kwaoo.net>;tag=ed1530ada8e777c4
        To: <sip:test.phone.kwaoo.net>
        Call-ID: 15591da1-15214f60@192.168.1.106
        CSeq: 55159 SUBSCRIBE
        Max-Forwards: 69
        Contact: <sip:0972222713@192.168.1.106:5063>
        Expires: 2147483647
        Event: message-summary
        User-Agent: Linksys/SPA962-6.1.5(a)
        Content-Length: 0
        \n
      '''

      test_msg2 = '''
        SUBSCRIBE sip:0972369812@a.phone.kwaoo.net SIP/2.0
        X-CCNQ3-Endpoint: 0972369812@a.phone.kwaoo.net
        Via: SIP/2.0/UDP 89.36.202.179:5060;branch=z9hG4bKddcd4dd080f01129f7749721fb029c7b;rport
        From: "0478182907" <sip:0972369812@a.phone.kwaoo.net>;tag=494263519
        To: "0478182907" <sip:0972369812@a.phone.kwaoo.net>
        Call-ID: 2516407383@192_168_1_2
        CSeq: 10319968 SUBSCRIBE
        Contact: <sip:0972369812@89.36.202.179:5060>
        Max-Forwards: 69
        User-Agent: C610 IP/42.075.00.000.000
        Event: message-summary
        Expires: 3600
        Allow: NOTIFY
        Accept: application/simple-message-summary
        Content-Length: 0
        \n
      '''

      assert.strictEqual (Parser.parseMessage test_msg1.replace(/\n/g,'\r\n'), null).method, 'SUBSCRIBE'
      assert.strictEqual (Parser.parseMessage test_msg2.replace(/\n/g,'\r\n'), null).method, 'SUBSCRIBE'
      assert.strictEqual typeof (Parser.parseMessage test_msg1.replace(/\n/g,'\r\n'), null).ruri.user, 'undefined'
      assert.strictEqual (Parser.parseMessage test_msg2.replace(/\n/g,'\r\n'), null).ruri.user, '0972369812'
      assert.strictEqual (Parser.parseMessage test_msg2.replace(/\n/g,'\r\n'), null).event.event, 'message-summary'

      test_msg1 = null
      test_msg2 = null


    do _test

