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

<hr>

<h1>Basic Framework</h1>
<ul>
  <h2>WebSocket Support</h2>
  <p>All Communcations go over the WebSocket protocol. 
    <i>(*Except for the nodelist collection through https)</i>
  </p>
  <h2>JSON Communcations</h2>
  <p>All Communcations are spoken with the JSON protocol.</p>
  <h2>Ed25519 Encryption</h2>
  <p>All Encryption needed is the Ed25519 Sign Function for Signatures with your Wallets Public and Private Keys.</p>
</ul>

<hr>

<h1>New Wallet</h1>
<ul>
  <h2>0. http-get Wallet</h2>
  <ul>
    <h3>For easy purpose only. For details about creating the wallet yourself, see FCC::wallet.pm</h3>
    <p>FCC Wallet :  <a href="https://factorialcoin.nl:5151/?wallet" target="_blank"><pre><code>https://factorialcoin.nl:5151/?wallet</code></pre></a></p>
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
    <p>PTTP Wallet : <a href="https://factorialcoin.nl:9612/?wallet" target="_blank"><pre><code>https://factorialcoin.nl:9612/?wallet</code></pre></a></p>
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

<hr>

<h1>Wallet-Leaf Connection Protocol</h1>
<ul>
  <h2>0. http-get Nodelist</h2>
  <ul>
    <p><a href="https://factorialcoin.nl:5151/?nodelist" target="_blank"><pre><code>https://factorialcoin.nl:5151/?nodelist</code></pre></a></p>
    <p><pre>returns FCC Nodelist : <code>[node-ip]:[node-port][space][...]</code></pre></p>
    <p><a href="https://factorialcoin.nl:9612/?nodelist" target="_blank"><pre><code>https://factorialcoin.nl:9612/?nodelist</code></pre></a></p>
    <p><pre>returns PTTP Nodelist : <code>[node-ip]:[node-port][space][...]</code></pre></p>
  </ul>
  <p><i><strong>*** After setting up your WebSocket Connection to the node ... the node will react with JSON commands ***</strong></i></p>
  <h2>1. in < command:hello</h2>
  <ul>
    <p><pre><code>{
  "command":"hello",
  "host":"[node-ip]",
  "port":"[node-port]",
  "version":"[fcc-ledger-version]"
}</code></pre></p>
  </ul>
  <h2>2. out > command:identify</h2>
  <ul>
  <p><pre><code>{
  "command":"identify",
  "type":"leaf",
  "version":"[fcc-ledger-version]" (we use 0101 to start with)
}</code></pre></p>
  </ul>
  <p><i><strong>*** After this react with the following JSON commands ***</strong></i></p>
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
      "fee":[percentage * 100 (integer 100% = 10000, 0.5% = 50)]
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
  octhex (
    Crypt::Ed25519::sign (
      [transaction-ledger-data-to-sign],
      hexoct ( [your-wallet-public-key] ),
      hexoct ( [your-wallet-private-key] )
    )
  );
</code></pre>
        <p>* <strong>octhex</strong> translates binary data into hexadecimal data</p>
        <p>* <strong>hexoct</strong> translates hexadecimal data into binary data</p>
        <p>* <strong>Crypt::Ed25519::sign</strong> signs your data with your private and public keys</p>
      </p>
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

<hr>

<h1>Miner-Leaf Connection Protocol</h1>
<ul>
  <h2>0. http-get Nodelist</h2>
  <ul>
    <p><a href="https://factorialcoin.nl:5151/?nodelist" target="_blank"><pre><code>https://factorialcoin.nl:5151/?nodelist</code></pre></a></p>
    <p><pre>returns FCC Nodelist : <code>[node-ip]:[node-port][space][...]</code></pre></p>
    <p><a href="https://factorialcoin.nl:9612/?nodelist" target="_blank"><pre><code>https://factorialcoin.nl:9612/?nodelist</code></pre></a></p>
    <p><pre>returns PTTP Nodelist : <code>[node-ip]:[node-port][space][...]</code></pre></p>
  </ul>
  <p><i><strong>*** After setting up your WebSocket Connection to the node ... the node will react with JSON commands ***</strong></i></p>
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
  <p><i><strong>*** After this react with the following JSON commands ***</strong></i></p>
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

<hr>
