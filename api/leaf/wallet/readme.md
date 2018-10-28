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
    <p><code>{"command":"hello","host":"[node-ip]","port":"[node-port]","version":"[fcc-version]"}</code></p>
  </ul>
  <h2>Identify out</h2>
  <ul>
    <p><code>{"command":"identify","type":"leaf","version":"[fcc-version]"}</code></p>
  </ul>
</ul>

<h1>Connected Wallet Leaf Commands</h1>
<ul>
  <h2>Wallet Balance</h2>
  <ul>
    <h3>out > command:balance</h3>
    <ul>
      <p><code>{"command":"balance","wallet":"[fcc-wallet-address]"}</code></p>
    </ul>
    <h3>in < command:balance</h3>
    <ul>
      <p><code>{"command":"balance","wallet":"[fcc-wallet-address]","balance":[fccamount]}</code></p>
    </ul>
  </ul>
  <h2>Wallet Transaction</h2>
  <ul>
    <h3>out > command:</h3>
    <ul>
      <p><code>{}</code></p>
    </ul>
    <h3>in < command:</h3>
    <ul>
      <p><code>{}</code></p>
    </ul>
  </ul>
</ul>
