# Leaf Api Documentation

<ul>
  <li>Basic Framework</li>
  <ul>
    <li>WebSocket Support</li>
    <li>JSON Communcations</li>
    <li>Ed25519 Encryption</li>
  </ul>
  <li>New Wallet</li>
  <ul>
    <li>0. http-get wallet</li>
  </ul>
  <li>Wallet-Leaf Connection Protocol</li>
  <ul>
    <li>0. http-get Nodelist</li>
    <li>1. in < command:hello</li>
    <li>2. out > command:identify</li>
  </ul>
  <li>Connected Wallet-Leaf Commands</li>
  <ul>
    <li>Wallet Balance</li>
    <ul>
      <li>1. out > command:balance</li>
      <li>2. in < command:balance</li>
      <ul>
        <li>a. when error occured</li>
        <li>b. on success</li>
      </ul>
    </ul>
    <li>Wallet Transaction</li>
    <ul>
      <li>1. out > command:transfer</li>
      <li>2. in < command:newtransaction</li>
      <ul>
        <li>a. when error occured</li>
        <li>b. on success</li>
      </ul>
      <li>3. out > command:signtransaction</li>
      <ul>
        <li>a. formulating the signature</li>
      </ul>
      <li>4. in < command:signtransaction</li>
      <ul>
        <li>a. when error occured</li>
        <li>b. on success</li>
      </ul>
      <li>5. in < command:processed</li>
      <ul>
        <li>a. when error occured</li>
        <li>b. on success</li>
      </ul>
    </ul>
  </ul>
  <li>Miner-Leaf Connection Protocol</li>
  <ul>
    <li>0. http-get Nodelist</li>
    <li>1. in < command:hello</li>
    <li>2. out > command:identify</li>
  </ul>
  <li>Connected Miner-Leaf Commands</li>
  <ul>
    <li>1. out > command:mine</li>
    <li>2. in < command:challenge</li>
  </ul>
</ul>

<h1>Basic Framework</h1>
<ul>
  <h2>WebSocket Support</h2>
  <p>All Communcations go over the WebSocket protocol. 
    <i>(*Except for the nodelist collection thru https)</i>
  </p>
  <h2>JSON Communcations</h2>
  <p>All Communcations are spoken with the JSON protocol.</p>
  <h2>Ed25519 Encryption</h2>
  <p>All Encryption needed is the Ed25519 Sign Function for Signatures with your Wallets Public and Private Keys.</p>
</ul>

<h1>New Wallet</h1>
<ul>
  <h2>0. http-get Wallet</h2>
  <ul>
    <p><pre><code>https://factorialcoin.nl:5151/?wallet</code></pre></p>
    <p>returns : <pre><code>{
  "encryted":0,
  "wlist":[
    {
      "name":"[ No name ]",
      "wallet":"[FCC-WALLET-ADDRESS]",
      "pubkey":"[PUBLIC-KEY]",
      "privkey":"[PRIVATE-KEY]"
    }
  ]
}</code></pre></p>
    <p><pre><code>https://factorialcoin.nl:9612/?wallet</code></pre></p>
    <p>returns : <pre><code>{
  "encryted":0,
  "wlist":[
    {
      "name":"[ No name ]",
      "wallet":"[PTTP-WALLET-ADDRESS]",
      "pubkey":"[PUBLIC-KEY]",
      "privkey":"[PRIVATE-KEY]"
    }
  ]
}</code></pre></p>
  </ul>
</ul>
<h1>Wallet-Leaf Connection Protocol</h1>
<ul>
  <h2>0. http-get Nodelist</h2>
  <ul>
    <p><pre><code>https://factorialcoin.nl:5151/?nodelist</code></pre></p>
    <p><pre>returns : <code>[node-ip]:[node-port][space][...]</code></pre></p>
  </ul>
  <h2>1. in < command:hello</h2>
  <ul>
    <p><pre><code>{
  "command":"hello",
  "host":"[node-ip]",
  "port":"[node-port]",
  "version":"[fcc-version]"
}</code></pre></p>
  </ul>
  <h2>2. out > command:identify</h2>
  <ul>
  <p><pre><code>{
  "command":"identify",
  "type":"leaf",
  "version":"[fcc-version]"
}</code></pre></p>
  </ul>
</ul>

<h1>Connected Wallet-Leaf Commands</h1>
<ul>
  <h2>Wallet Balance</h2>
  <ul>
    <h3>1. out > command:balance</h3>
    <ul>
      <p><pre><code>{
  "command":"balance",
  "wallet":"[fcc-wallet-address]"
}</code></pre></p>
    </ul>
    <h3>2. in < command:balance</h3>
    <ul>
      <h4>a. when error occured</h4>
      <p><pre><code>{
  "command":"balance",
  "error":"[error-message]"
}</code></pre></p>
      <h4>b. on success</h4>
      <p><pre><code>{
  "command":"balance",
  "wallet":"[fcc-wallet-address]",
  "balance":[fccamount]
}</code></pre></p>
    </ul>
  </ul>
  <h2>Wallet Transaction</h2>
  <ul>
    <h3>1. out > command:transfer</h3>
    <ul>
      <p><pre><code>{
  "command":'newtransaction',
  "transid":[your-transaction-idnr],
  "pubkey":"[wallet-pubkey]",
  "to":[
    {
      "wallet":"[wallet-address]",
      "amount":[doggy],
      "fee":[doggy]
    }, ..
  ]
}</code></pre></p>
    </ul>
    <h3>2. in < command:newtransaction</h3>
    <ul>
      <h4>a. when error occured</h4>
      <p><pre><code>{
  "command":"newtransaction",
  "transid":[your-transaction-idnr],
  "error":"[error-message]"
}</code></pre></p>
      <h4>b. on success</h4>
      <p><pre><code>{
  "command":"newtransaction",
  "transid":[your-transaction-idnr],
  "sign":"[transaction-ledger-data-to-sign]",
  "fcctime":[fcctimestamp]
}</code></pre></p>
    </ul>
    <h3>3. out > command:signtransaction</h3>
    <ul>
      <p><pre><code>{
  "command":'signtransaction',
  "transid":[your-transaction-idnr],
  "signature":[your-transaction-ledger-data-signature]
}</code></pre></p>
      <h4>a. formulating the signature in [Perl Code]</h4>
      <p><pre><code>
[your-transaction-ledger-data-signature] =
  octhex(
    Crypt::Ed25519::sign(
      [transaction-ledger-data-to-sign],
      hexoct([wallet_pubkey]),
      hexoct([wallet_privkey])
    )
  );
      </code></pre></p>
    </ul>
    <h3>4. in < command:signtransaction</h3>
    <ul>
      <h4>a. when error occured</h4>
      <p><pre><code>{
  "command":"signtransaction",
  "transid":[your-transaction-idnr],
  "error":"[error-message]"
}</code></pre></p>
      <h4>b. on success</h4>
      <p><pre><code>{
  "command":"signtransaction",
  "transid":[your-transaction-idnr],
  "transhash":"[node-transaction-id]"
}</code></pre></p>
    </ul>
    <h3>5. in < command:processed</h3>
    <ul>
      <h4>a. when error occured</h4>
      <p><pre><code>{
  "command":"processed",
  "transhash":"[node-transaction-id]",
  "error":"[error-message]" 
}</code></pre></p>
      <h4>b. on success</h4>
      <p><pre><code>{
  "command":"processed",
  "transhash":"[node-transaction-id]",
  "wallet":"[wallet-address]",
  "status":"success"
}</code></pre></p>
    </ul>
  </ul>
</ul>

<h1>Miner-Leaf Connection Protocol</h1>
<ul>
  <h2>0. http-get Nodelist</h2>
  <ul>
    <p><pre><code>https://factorialcoin.nl:5151/?nodelist</code></pre></p>
    <p><pre>returns : <code>[node-ip]:[node-port][space][...]</code></pre></p>
  </ul>
  <h2>1. in < command:hello</h2>
  <ul>
    <p><pre><code>{
  "command":"hello",
  "host":"[node-ip]",
  "port":"[node-port]",
  "version":"[fcc-version]"
}</code></pre></p>
  </ul>
  <h2>2. out > command:identify</h2>
  <ul>
  <p><pre><code>{
  "command":"identify",
  "type":"miner",
  "version":"[fcc-version]"
}</code></pre></p>
  </ul>
</ul>

<h1>Connected Miner-Leaf Commands</h1>
<ul>
  <h2>1. out > command:mine</h2>
  <ul>
    <p><pre><code>{
  "command":"mine"
}</code></pre></p>
  </ul>
  <h2>2. in < command:mine</h2>
  <ul>
    <p><pre><code>{
  "command":"mine",
  "challenge":"[ANSWER]",
  "coincount":[CBCOUNT],
  "diff":[DIFF],
  "length":[DFAC],
  "hints":"[HINTSTR]",
  "ehints":"[EHINTSTR]",
  "reward":[MINERPAYOUT],
  "time":[FCCTIME],
  "lastsol":"[LASTSOL]"
}</code></pre></p>
  </ul>
  <h2>3. out > command:solution</h2>
  <ul>
    <p><pre><code>{
  "command":"solution",
  "solhash":"[SOLUTION_HASH]",
  "wallet":[wallet-address]
}</code></pre></p>
  </ul>
  <h2>4. in < command:solution</h2>
  <ul>
    <h3>a. on error</h3>
    <p><pre><code>{
  "command":"solerr"
}</code></pre></p>
    <h3>b. on success</h3>
    <p><pre><code>{
  "command":"solution"
}</code></pre></p>
  </ul>
</ul>