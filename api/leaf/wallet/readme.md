# Wallet Leaf Api Documentation

<ul>
  <li>Basic Framework</li>
  <ul>
    <li>WebSocket Support</li>
    <li>JSON Communcations</li>
  </ul>
  <li>Wallet Leaf Connection Protocol</li>
  <ul>
    <li>Hello in</li>
    <li>Identify out</li>
  </ul>
  <li>Connected Wallet Leaf Commands</li>
  <ul>
    <li>Wallet Balance</li>
    <li>Wallet Transaction</li>
  </ul>
</ul>

<h1>Basic Framework</h1>
<ul>
  <h2>WebSocket Support</h2>
  <p>All Communcations go over the WebSocket protocol.</p>
  <h2>JSON Communcations</h2>
  <p>All Communcations are spoken with the JSON protocol.</p>
</ul>


<h1>Wallet Leaf Connection Protocol</h1>
<ul>
  <h2>Hello in</h2>
  <ul>
    <p><pre><code>{
  "command":"hello",
  "host":"[node-ip]",
  "port":"[node-port]",
  "version":"[fcc-version]"
}</code></pre></p>
  </ul>
  <h2>Identify out</h2>
  <ul>
  <p><pre><code>{
  "command":"identify",
  "type":"leaf",
  "version":"[fcc-version]"
}</code></pre></p>
  </ul>
</ul>

<h1>Connected Wallet Leaf Commands</h1>
<ul>
  <h2>Wallet Balance</h2>
  <ul>
    <h3>out > command:balance</h3>
    <ul>
      <p><pre><code>{
  "command":"balance",
  "wallet":"[fcc-wallet-address]"
}</code></pre></p>
    </ul>
    <h3>in < command:balance</h3>
    <ul>
      <p><pre><code>{
  "command":"balance",
  "wallet":"[fcc-wallet-address]",
  "balance":[fccamount]
}</code></pre></p>
    </ul>
  </ul>
  <h2>Wallet Transaction</h2>
  <ul>
    <h3>out > command:transfer</h3>
    <ul>
      <p><pre><code>{
  command => 'newtransaction',
  transid => [your-transaction-id],
  pubkey => [wallet-pubkey],
  to => [tolist]
}</code></pre></p>
    </ul>
    <h3>in < command:sign</h3>
    <ul>
      <p><pre><code>{
  command=>'newtransaction',
  transid=>[your-transaction-id],
  sign=>[transaction-ledger-data-to-sign],
  fcctime=>[fcctimestamp]
}</code></pre></p>
    </ul>
    <h3>out > command:sign</h3>
    <ul>
      <p><pre><code>{
  command => 'signtransaction',
  transid => [your-transaction-id],
  signature => [your-signature]
}</code></pre></p>
    </ul>
  </ul>
</ul>
