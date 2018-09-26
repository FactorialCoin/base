
  var wserver = 'ws://127.0.0.1:$PORT';
  var connected = 0;
  var beenconnected = 0;
  var activewallet = "";
  var passbusy = 0;
  var wallets = {};
  var eabmode = 0;
  var solutionFound=0;
  var wins=0;
  var lost=0;
  var miningstart=1;
  var mtime=Date.now()/1000;
  var miningwallet;

  function chatout(txt) {
    var st=document.getElementById('status');
    st.innerHTML = st.innerHTML + "<br />" + txt;
    st.scrollTop=st.scrollHeight;
  }
  
  function wininfo(){
    var avgwin=(wins+lost) ? Math.floor((100/(wins+lost))*wins*100)/100 : 0;
    if(document.getElementById('coinwon')) document.getElementById('coinwon').innerHTML="("+avgwin+"%) "+wins+" of "+(wins+lost);
  }
  
  function mineout(txt) {
    var st=document.getElementById('mineoutput');
    if ((/New challenge:/gi).test(txt) || (/Next challenge:/gi).test(txt)) {
      var sd=document.getElementById('minediff');
      var arg = txt.replace('New challenge: ','').replace('Next challenge: ','').split(' ');
      var cha={ // Next challenge: Coincount = 4709 Difficulty = 479001600 Reward = 1000000000 Len = 13 Hints = AL eHints = EHKJAL Init = LJAF
        coin: arg[2],
        diff: arg[5],
        rewa: arg[8],
        leng: arg[11],
        hint: arg[14] ? arg[14].split('') : '',
        ehint: arg[17] ? arg[17].split('') : '',
        init: arg[20] ? arg[20].split('') : ''
      };
      cha.hint.sort();
      if ((/New challenge:/gi).test(txt)) {
        mtime=Date.now()/1000;
        drawDiff(Number(cha.diff));
        drawCoin(0);
      }
      sd.innerHTML =
      '<table cellspacing=0 cellpadding=0 border=0 id="cointable">'+
        '<tr><th>Reward:</th><td id="coinreward">'+cha.rewa+'</td><th>Won:</th><td id="coinwon"></td></tr>'+
        '<tr><th>Coincount:</th><td id="coincount">'+cha.coin+'</td><th>Fh/s:</th><td id="coinfhs">0</td></tr>'+
        '<tr><th>Difficulty:</th><td id="coindiff" title="'+cha.diff+'">'+kstr(cha.diff)+'</td><th>Mined:</th><td id="coinprc">0%</td></tr>'+
        '<tr><th>Length:</th><td id="coinlength">'+cha.leng+'</td><th>Sec:</th><td id="coinsec">0</td></tr>'+
        '<tr><th>Hints:</th><td id="coinhint">'+cha.hint.length+'</td><td colspan="2">'+cha.hint.join(',')+'</td></tr>'+
      '</table>';
      wininfo();
      if((/New challenge:/gi).test(txt)){
        if(solutionFound || miningstart) { solutionFound=0; miningstart=0 }
        else{
          var st=document.getElementById('mineoutput');
          st.innerHTML += "<br><font color='red'> Lost This Round :-/ </font>";
          lost++;
          addStat(0);
        }
      }
    }
    else if ((/Speed:/gi).test(txt)) {
      var cp=document.getElementById('coinprc');
      var cs=document.getElementById('coinsec');
      var cf=document.getElementById('coinfhs');
      var sd=document.getElementById('minespeed');
      var mtm=Date.now()/1000;
      var sec=Math.floor(mtm-mtime);
      sd.innerHTML = txt.replace('Speed: ','');
      var fhs=drawSpeed(sd.innerHTML);
      timeCoin(sec);
      cs.innerHTML = sec;
      cf.innerHTML = kstr(fhs[0]);
      cp.innerHTML = fhs[1]+'%';
    }
    else if ((/Found solution/gi).test(txt)) {
      st.innerHTML += "<br>" + txt;
      wins++;
      wininfo();
      solutionFound=1;
      addStat(1);
    }
    else{
      wininfo();
      st.innerHTML += "<br>" + txt;
      var lines=(st.innerHTML+"").split('<br>');
      if (lines.length>10) {
        lines.shift();
        st.innerHTML = lines.join("<br>");
      }
    }
    st.scrollTop=st.scrollHeight;
  }

function kstr (num) {
  var nl=(num+"").split('');
  var ni=0,os="";
  for(var i=nl.length-1;i>=0;i--){
    os=nl[i]+os;
    ni++; if(ni == 3 && i>0){ ni=0; os="."+os }
  }
  return os
}
var discon=0;
  function connect() {
    if ("WebSocket" in window) {
      chatout("** WebSockets supported ..<br />** Opening WebSocket on " + wserver + " ..");
    } else if (window.MozWebSocket) {
      chatout("*** WebSockets supported (Mozilla) ..<br />** Opening WebSocket on " + wserver + " ..");
      window.WebSocket=window.MozWebSocket;
    } else {
      chatout("** WebSockets NOT supported !! You won't be able to use this software in this brwoser! Upgrade your browser!!!!");
      return
    }
    socket = new WebSocket(wserver);
    socket.onopen = function() {
      chatout("** Connected to the WebSocket Server");
      connected=1; beenconnected=1;
      socket.send('init');
      document.getElementById('powerbutton').style.background='rgba(127,255,127,0.6)';
    }
    socket.onmessage = function(evt) {
      // arg is usally the time !!!!
      var ml=evt.data.split(" ");
      var target=ml.shift(); var arg=ml[0]; var par=ml[1]; var txt=ml.join(" ");
      if (target == 'status') {
      	chatout(txt)
        if(txt.indexOf("Disconnected from node") !== -1){
          discon=1
        }
        if (discon && txt.indexOf("Connected to node") !== -1 && miningwallet){
          discon=0;
          chatout('* Restarting miner for wallet '+miningwallet+'.');
          startminer(miningwallet);
        } 
      }
      else if (target == 'miner') {
        mineout(txt)
      }
      else if (target == 'mining') {
        var msg;try{eval('msg='+txt);}catch(e){alert(e);return};
        mineout(
          "New challenge:"+
          " Coincount = "+msg.data.coincount+
          " Difficulty = "+msg.data.diff+
          " Reward = "+msg.data.reward+
          " Len = "+msg.data.length+
          " Hints = "+msg.data.hints
        );
        mineout('Already running attached Miner');
        if(mnh==null||mnh > msg.size[0]) mnh=msg.size[0];
        if(mxh==null||mxh < msg.size[1]) mxh=msg.size[1];
        startminer(msg.wallet);
        miningwallet=msg.wallet;
      }
      else if (target == 'node') {
      	setnode(arg)
      }
      else if (target == 'getpass') {
      	document.getElementById('graybg').style.visibility='visible';
      	document.getElementById('passbox').style.visibility='visible';
      	document.getElementById('wachtwoord').focus();
      	passbusy=1
      }
      else if (target == 'passok') {
      	document.getElementById('graybg').style.visibility='hidden';
      	document.getElementById('passbox').style.visibility='hidden';
      	passbusy=0
      }
      else if (target == 'passinvalid') {
      	document.getElementById('passerr').innerHTML='Invalid password. Please try again';
      }
      else if (target == 'addwallet') {
      	var wallet=ml.shift(); var name=ml.join(" ");
      	addwallet(wallet,name);
        activatewallet(wallet);
      }
      else if (target == 'actwal') {
      	activatewallet(arg)
      }
      else if (target == 'balance') {
      	setbalance(arg,par)
      }
      else if (target == 'adrbook') {
      	var wallet=ml.shift(); var name=ml.join(" ");
      	adrbook(wallet,name)
      }
      else if (target == 'transerr') {
      	transerr(txt)
      }
      else if (target == 'transok') {
        transok(arg,par,ml[2],ml[3])
      }
      else if (target == 'transtotal') {
      	document.getElementById('transtotal').innerHTML=arg
      }
      else if (target == 'powerdownnow'){
        window.close();
      }
    }
    socket.onclose = function() {
      if (connected) {
        document.getElementById('powerbutton').style.background='rgba(255,0,0,0.5)';
        chatout("** Lost connection to the WebSocket Server. Please refresh.");
      }
      gorefresh()
    }
    socket.onerror = function() {
      if (connected) {
        chatout("** WebSocket Server Error. Please refresh.");
      } else {
      	chatout("** The WebSocket Server is offline. Please restart FCC.")
      }
      document.getElementById('powerbutton').style.background='rgba(255,0,0,0.5)';
      gorefresh()
    }
  }
  function start() {
  	connect();
    document.getElementById('body').style.backgroundImage="url(image/fccbg.png)";
    $AUTOSTART
  }
  function powerDownWallet(){
    socket.send('powerdown');
  }
  function savechatnick(nick){
    socket.send('savechat nick '+nick);
  }
  function savechatident(ident){
    socket.send('savechat ident '+ident);
  }
  function savechatauto(checked){
    socket.send('savechat auto '+(checked?"1":"0"));
  }
  function savechatzoom(zoom){
    socket.send('savechat zoom '+zoom);
    chatzoom()
  }
  function gorefresh() {
  	document.getElementById('graybg').style.visibility='visible';
  	document.getElementById('refresh').style.visibility='visible';
  }
  function checkenter(e,id) {
    if (e.which == 13 || e.keyCode == 13) { 
      var obj = document.getElementById(id);
      obj.select(); obj.focus()
    }
  }
  function checksubmit(e,id) {
    if (e.which == 13 || e.keyCode == 13) { 
      var obj = document.getElementById(id);
      obj.click();
    }
  }
  function checkdigit(e,id) {
  	var txt=document.getElementById(id).value;
  	txt = txt.replace(",",".");
  	txt = txt.replace(/[^0-9.]/g,"");
  	document.getElementById(id).value=txt
  }
  function checkhexpaste(id) {
  	var txt=document.getElementById(id).value;
  	txt = txt.toUpperCase();
  	txt = txt.replace(/[^0-9A-F]/g,"");
  	document.getElementById(id).value=txt
  }
  function checkhex(e,id) {
  	checkhexpaste(id)
  }
  function checkpass() {
  	var pass = document.getElementById("wachtwoord").value;
  	socket.send('pass ' + pass)
  }
  function passprotect() {
  	if (passbusy) { return }
   	document.getElementById('graybg').style.visibility='visible';
   	document.getElementById('newpassbox').style.visibility='visible';
  	document.getElementById('newpasserr').innerHTML="";
   	document.getElementById('newpass').focus();
   	document.getElementById('newpass').select();
  }
  function cancelnewpass() {
   	document.getElementById('graybg').style.visibility='hidden';  	
   	document.getElementById('newpassbox').style.visibility='hidden';  	
  }
  function setnewpass() {
  	document.getElementById('newpasserr').innerHTML="";
   	var pass=document.getElementById('newpass').value;
   	if (pass != '') {
   		var vld=document.getElementById('newpassvld').value;
   		if (vld != pass) {
   			document.getElementById('newpasserr').innerHTML='The passwords are not the same'
   		}
   		else {
        socket.send("newpass " + pass);
      	document.getElementById('graybg').style.visibility='hidden';
      	document.getElementById('newpassbox').style.visibility='hidden';
   		}
   	}
   	else {
   		document.getElementById('newpasserr').innerHTML='No password given'
   	}
  }
  function setnode(node) {
  	document.getElementById('node').innerHTML="Node: " + node;
  }
  function addwallet(wallet,name) {
    var wal=document.createElement("DIV");
    wal.id='R' + wallet;
    wal.classList.add("rwal");
    document.getElementById("wallets").appendChild(wal);
    
    var obj=document.createElement("DIV");
    obj.id='W' + wallet;
    obj.classList.add("iwal");
    obj.classList.add("muis");
    obj.innerHTML=(name != "" ? name + " (" + wallet + ")" : wallet);
    obj.addEventListener("click",function() { activatewallet(this.id.substring(1)) },false);
    wal.appendChild(obj);

    var obj=document.createElement("IMG");
    obj.id='C' + wallet;
    obj.src="image/clipboard.png";
    obj.width='32px';
    obj.classList.add("cwal");
    obj.classList.add("muis");
    obj.addEventListener("click",function() { copywal(this.id.substring(1)) },false);
    wal.appendChild(obj);

  	wallets[wallet]=name
  }
  function activatewallet(wallet) {
  	document.getElementById("wallet").innerHTML=wallet;
  	document.getElementById("from").innerHTML="[ no name ] (" + wallet + ")";
  	document.getElementById("walname").style.visibility='visible';
	  document.getElementById("copywallet").style.visibility='visible';
	  document.getElementById("savewalbut").style.visibility='visible';
    if (activewallet != "") {
      document.getElementById(activewallet).style.background='#cceeff';
      document.getElementById(activewallet).style.color='#2060a0';
    }
  	socket.send('balance ' + wallet);
  	var wobj = 'W' + wallet;
  	document.getElementById(wobj).style.background='#20aa60';
  	document.getElementById(wobj).style.color='#ffffff';
  	var wname=document.getElementById(wobj).innerHTML;
  	var ws=wname.split(" "); ws.pop(); wname=ws.join(" ");
  	document.getElementById("walname").value=wname;
  	if (wname) {
	  	document.getElementById("from").innerHTML=wname + " (" + wallet + ")";
  	}
  	var i; var cwo=document.getElementById("change"); var cwl=cwo.options;
  	for (i=cwl.length-1;i>=0;i--) { cwo.remove(i) }
  	var cho=document.createElement("OPTION");
    cho.value=wallet;
    cwo.add(cho);
    cwo.selectedIndex=0;
    var wl=document.getElementById("wallets").children;
    for (i=1;i<wl.length;i++) {
    	if (wl[i].id.substr(1) != wallet) {
      	var cho=document.createElement("OPTION");
        cho.value=wl[i].id.substr(1);
        cho.text=wl[i].id.substr(1);
        cwo.add(cho);
    	} else {
    		cwo.options[0].text=wl[i].id.substr(1);
    	}
    }
    document.getElementById('pickaxe').style.display = (new RegExp(wallet)).test(document.getElementById('minewallet').innerHTML) ? 'block':'none';
  	activewallet=wobj
  }
  function setbalance(balance,wallet) {
  	if (document.getElementById("wallet").innerHTML == wallet) {
  	  document.getElementById("balance").innerHTML=balance;
     	  showdelwal(balance)
  	}
  }
  function getwallet() {
  	return document.getElementById("wallet").innerHTML
  }
  function createwallet() {
  	if (passbusy) { return }
  	socket.send("createwallet")
  }
  function openchat() {
    var obj=document.getElementById('chatframe');
    var n=document.getElementById('chatnick').value;
    var p=document.getElementById('identpass').value;
    document.getElementById('chatcont').style.border='0px';
    var c="http://chat.lichtsnel.nl?channel=crypto" + ( n ? '&autologin=1&nick='+escape(n)+( p ? '&pass='+escape(p) : '') : '');
    if (obj) {
      if(confirm('Reopen the Chat Window?')){
        obj.src=c;
      }
    } else {
      document.getElementById('openchat').innerHTML='&nbsp;&nbsp;Reopen Chatbox';
      document.getElementById('chatzoom').style.display='block';
      var ct=document.getElementById('chatcont');
      obj=document.createElement("IFRAME");
      obj.id='chatframe';
      obj.src=c;
      obj.scrolling="no";
      ct.appendChild(obj);
      chatzoom()
    }
  }
  function chatzoom() {
    var cz=document.getElementById('chatzoom'), zm=cz.options[cz.selectedIndex].value, zp=(100/(zm/100));
    var cf=document.getElementById('chatframe');
    if(cf){
      if(cf.classList.length>0) cf.classList.remove(cf.classList.item(0));
      cf.classList.add("zm"+zm);
      cf.style.width=zp+'%';
      cf.style.height=zp+'%';
    }
  }
  function savewalname() {
  	var name=document.getElementById("walname").value;
  	var wallet=getwallet();
  	if (wallet.length == 68) {
  	  socket.send("setname " + wallet + " " + name);
  	  wallets[wallet]=name
  	}
  	var wid="W" + wallet;
  	document.getElementById(wid).innerHTML=name + " (" +wallet + ")";
  }
  function copywal(w) {
  	var txt=w||document.getElementById("wallet").innerHTML;
  	if (window.clipboardData && window.clipboardData.setData) {
      // IE specific code path to prevent textarea being shown while dialog is visible.
      clipboardData.setData("Text", txt);
    }
    else if (document.queryCommandSupported && document.queryCommandSupported("copy")) {
      var textarea = document.createElement("textarea");
      textarea.textContent = txt;
      textarea.style.position = "fixed";  // Prevent scrolling to bottom of page in MS Edge.
      document.body.appendChild(textarea);
      textarea.select();
      try {
        document.execCommand("copy");  // Security exception may be thrown by some browsers.
    	  document.getElementById("copied").innerHTML="Copied to clipboard";
      } catch (ex) {
    	  document.getElementById("copied").innerHTML="NOT copied. " + ex;
      } finally {
        document.body.removeChild(textarea);
      }
    }
  	window.setTimeout(function(){ document.getElementById("copied").innerHTML="";},1750)
  }
  function showdelwal(balance) {
  	if (balance == '0.00000000') {
  	  document.getElementById("delwalbut").style.visibility='visible'
  	}
  	else {
  	  document.getElementById("delwalbut").style.visibility='hidden'  		
  	}
  }
  function delwal() {
  	if (window.confirm("ARE YOU SURE ?\n\nAlthough this wallet is now empty,\nif you have ever published it,\nit still may receive money in the future.\n\nOnly confirm if you have never published this wallet.")) {
  		var wallet=getwallet();
  		socket.send('delwallet ' + wallet);
  	  document.getElementById("delwalbut").style.visibility='hidden';
  	  document.getElementById("copywallet").style.visibility='hidden';
  	  document.getElementById("savewalbut").style.visibility='hidden';
  	  document.getElementById("wallet").innerHTML="[none]";
  	  document.getElementById("from").innerHTML="[none]";
    	document.getElementById("walname").style.visibility='hidden';
  	  document.getElementById("balance").innerHTML="";
  	  var obj=document.getElementById("R" + wallet);
    	document.getElementById("wallets").removeChild(obj);
    	activewallet="";
    	var wlist=document.getElementById("wallets").children;
    	if (wlist.length>1) {
        activatewallet(wlist[1].id.substr(1))
      }
  	}
  }
  function startminer(w) {
    var wallet = w||getwallet();
    document.getElementById('minewallet').innerHTML=wallet + (wallets[wallet] ? '<br>'+wallets[wallet]:'');
    document.getElementById('minerrunning').style.display='block';
    document.getElementById('minerstopped').style.display='none';
    document.getElementById('miner').style.display='block';
    document.getElementById('diffaxe').style.display = 'block';
    document.getElementById('pickaxe').style.display = (new RegExp(document.getElementById('wallet').innerHTML)).test(document.getElementById('minewallet').innerHTML) ? 'block':'none';
    mineout('Started Miner on '+wallet.substr(0,16)+'... !');
    miningwallet=wallet;
    socket.send('startminer ' + wallet)
  }
  function stopminer() {
    miningstart=1;
    document.getElementById('minewallet').innerHTML="";
    document.getElementById('minerrunning').style.display='none';
    document.getElementById('minerstopped').style.display='block';
    document.getElementById('miner').style.display='none';
    document.getElementById('diffaxe').style.display = 'none';
    document.getElementById('pickaxe').style.display = 'none';
    mineout('Miner stopped!');
    socket.send('stopminer')
  }
  function transerr(txt) {
  	if (eabmode) {
    	document.getElementById('aeerr').innerHTML=txt
  	} else {
  	  document.getElementById('transerr').innerHTML=txt
  	}
  }
  function adrbook(wallet,name) {
  	var option = document.createElement("option");
    option.text = name; option.value=wallet;
    document.getElementById('adrbook').add(option);
    wallets[wallet]=name
  }
  function setadrbook() {
  	var idx=document.getElementById('adrbook').selectedIndex;
  	var list=document.getElementById('adrbook').options;
  	var wallet=list[idx].value;
  	var name=list[idx].innerHTML;
  	document.getElementById('to').value=wallet;
  	document.getElementById('newadrbook').value=name;
  }
  function saveadrbook() {
  	transerr("");
  	var to=document.getElementById('to').value;
  	var name=document.getElementById('newadrbook').value;
  	if ((to != '') && (name != '')) {
  		socket.send('adrbook ' + to + ' ' + name);
    	document.getElementById('newadrbook').value=""
  	} else {
    	transerr("Please fill in a wallet-address and the name of the recipient")
  	}
  }
  function addtrans() {
  	transerr("");
  	var amount=document.getElementById('amount').value;
  	var fee=document.getElementById('fee').value;
  	var to=document.getElementById('to').value;
    if ((to != "") && (amount != "0.00000000")) {
    	socket.send('checktrans ' + to + ' ' + amount + ' ' + fee)
  	} else {
    	transerr("Please fill in an amount and the wallet-address of the recipient")
    }
  }
  function transok(nr,amount,fee,total) {
    var tout=document.createElement("DIV");
    tout.classList.add("transoutitem");
    tout.id='transout_' + nr;
    var wallet=document.getElementById('to').value;
    var name="[ No name ]";
    if (wallets[wallet] != null) { name=wallets[wallet] }

    var wout=document.createElement("DIV");
    wout.classList.add("walletout");
    wout.innerHTML=name + ' (' + wallet + ')';
    tout.appendChild(wout);

    var taout=document.createElement("DIV");
    taout.classList.add("totalout");
    taout.innerHTML=total;
    tout.appendChild(taout);

    var aout=document.createElement("DIV");
    aout.classList.add("amountout");
    aout.innerHTML="Amount: " + amount;
    tout.appendChild(aout);

    var fout=document.createElement("DIV");
    fout.classList.add("feeout");
    var spacing="";
    var ldec=amount.split("."); var dec=ldec[0]; var dn=dec.length;
    var lfdec=fee.split("."); var fdec=lfdec[0]; var dfn=fdec.length;
    while (dn>dfn) { spacing = spacing + '&nbsp;'; dn-- }
    fout.innerHTML="&nbsp;&nbsp;&nbsp;Fee: " + spacing + fee;
    tout.appendChild(fout);

    var dout=document.createElement("IMG");
    dout.id="delout_" + nr;
    dout.src="image/del.png";
    dout.height="26";
    dout.classList.add('delout');
    dout.classList.add('muis');
    dout.addEventListener("click",delout,false);
    tout.appendChild(dout);

    document.getElementById('transoutbox').appendChild(tout);
  }
  function delout(e) {
    var id=e.target.id; var lid=id.split("_"); var nr=lid[1];
    var obj=document.getElementById('transout_' + nr);
    document.getElementById('transoutbox').removeChild(obj);
    socket.send('deltrans ' + nr)
  }
  function transfer() {
  	var total=document.getElementById('transtotal').innerHTML;
  	var amount=document.getElementById('balance').innerHTML;
  	if (total == '0.00000000') {
  		transerr("No transactions to send")
  	} else if (parseFloat(amount) < parseFloat(total)) {
  		transerr("This wallet has insufficient funds to make this transaction")
  	} else {
    	document.getElementById('graybg').style.visibility='visible';
    	var wallet=document.getElementById("wallet").innerHTML;
    	var wbar=document.getElementById("W" + wallet).innerHTML;
    	document.getElementById("tcfrom").innerHTML=wbar;
    	document.getElementById("tctotal").innerHTML=total;
    	var chwal=document.getElementById('change');
    	document.getElementById("tcchange").innerHTML=chwal.options[chwal.selectedIndex].text;
     	var list=document.getElementsByClassName("tcoutblock");
     	var cf=document.getElementById("tcout");
     	var i;
     	for (i = list.length-1; i>=0; i--) {
        cf.removeChild(list[i])
      }
      var oblist=document.getElementsByClassName("transoutitem");
     	for (i = 0; i < oblist.length; i++) {
        var wobj=oblist[i].children[0];
        var aobj=oblist[i].children[2];
        var fobj=oblist[i].children[3];
        var vo=document.createElement("DIV");
        vo.classList.add("tcoutblock");
        var vow=document.createElement("DIV");
        vow.classList.add("tcoutwal");
        vow.innerHTML=wobj.innerHTML;
        vo.appendChild(vow)
        var voa=document.createElement("DIV");
        voa.classList.add("tcoutamount");
        voa.innerHTML=aobj.innerHTML.split(" ")[1];
        vo.appendChild(voa)
        var vof=document.createElement("DIV");
        vof.classList.add("tcoutfee");
        vof.innerHTML=fobj.innerHTML.split(" ")[1];
        vo.appendChild(vof);
        cf.appendChild(vo)
      }
     	document.getElementById('transconfirm').style.visibility='visible';
  	}
  }
  function tccancel() {
   	document.getElementById('transconfirm').style.visibility='hidden';
   	document.getElementById('graybg').style.visibility='hidden';
  }
  function tcok() {
  	tccancel();
   	var cf=document.getElementById("transoutbox");
    var list=document.getElementsByClassName("transoutitem");
   	var i;
   	for (i = 0; i < list.length; i++) {
      cf.removeChild(list[i])
    }
  	document.getElementById('amount').value='0.00000000';
  	document.getElementById('fee').value='0.5';
  	document.getElementById('to').value="";
  	document.getElementById('transtotal').innerHTML='0.00000000';
  	document.getElementById('adrbook').selectedIndex=0;
  	var wallet=getwallet(); var cobj=document.getElementById('change');
  	var chwal=cobj.options[cobj.selectedIndex].value;
  	socket.send('transfer ' + wallet + ' ' + chwal)
  }
  function aeerase() {
  	var cf=document.getElementById("ablist");
    var list=cf.children;
   	var i;
   	for (i = list.length-1; i>=0; i--) {
      cf.removeChild(list[i])
    }
  }
  function aefill() {
  	var list=document.getElementById('adrbook').options;
  	var i; var abl=document.getElementById("ablist");
  	for (i=1;i<list.length;i++) {
  		var wallet=list[i].value; var name=list[i].text;
  		var block=document.createElement("DIV");
      block.classList.add("abblock");
      var bw=document.createElement("DIV");
      bw.id='bw_' + i;
      bw.classList.add("abbwal");
      bw.innerHTML=wallet;
      block.appendChild(bw);
      var bnc=document.createElement("DIV");
      bnc.classList.add("abnc");
      var bn=document.createElement("INPUT");
      bn.id='bn_' + i;
      bn.classList.add("abbname");
      bn.value=name;
      bn.addEventListener('change',changeadrbook,false);
      bnc.appendChild(bn);
      block.appendChild(bnc);
      var bs=document.createElement("IMG");
      bs.id='bs_' + i;
      bs.classList.add("abbsave");
      bs.classList.add("muis");
      bs.src="image/save.png";
      bs.height="40";
      bs.addEventListener('click',changeadrbook,false);
      block.appendChild(bs);
      var bd=document.createElement("IMG");
      bd.id='bd_' + i;
      bd.classList.add("abbdel");
      bd.classList.add("muis");
      bd.src="image/del.png";
      bd.height="40";
      bd.addEventListener('click',deladrbook,false);
      block.appendChild(bd);
      abl.appendChild(block)
  	}  	
  }
  function changeadrbook(e) {
  	var id=e.target.id; var ids=id.split('_');
    var wallet=document.getElementById('bw_' + ids[1]).innerHTML;
    var name=document.getElementById('bn_' + ids[1]).value;
    document.getElementById('adrbook').options[ids[1]].text=name;
   	wallets[wallet]=name;
    socket.send("chadrbook " + wallet + ' ' + name)
  }
  function deladrbook(e) {
  	var id=e.target.id; var ids=id.split('_');
    var wallet=document.getElementById('bw_' + ids[1]).innerHTML;
    var name=document.getElementById('bn_' + ids[1]).value;
    if (confirm("Are you sure you want to delete wallet '" + name + "'\n(" + wallet + ") ?")) {
      socket.send('deladrbook ' + wallet);
      document.getElementById("adrbook").remove(ids[1]);
      aeerase(); aefill()
    }
  }
  function adrbookinterface() {
  	eabmode=1; transerr("");
  	document.getElementById('abnewwal').value="";
  	document.getElementById('abnewname').value="";
  	aefill();
   	document.getElementById('graybg').style.visibility='visible';
   	document.getElementById('editadrbook').style.visibility='visible';
  }
  function aeok() {
  	eabmode=0; aeerase();
   	document.getElementById('editadrbook').style.visibility='hidden';  	
   	document.getElementById('graybg').style.visibility='hidden';
  }
  function aeadd() {
  	transerr("");
  	var adr=document.getElementById('abnewwal').value;
  	var name=document.getElementById('abnewname').value;
  	if ((adr != '') && (name != '')) {
  		socket.send('adrbook ' + adr + ' ' + name);
  	} else {
    	transerr("Please fill in a wallet-address and the name of the recipient")
  	}
  }
  
  // canvas

  function drLine (ctx,x1,y1,x2,y2,w,c){
    ctx.lineWidth=w;
    ctx.strokeStyle=c;
    ctx.beginPath();
    ctx.moveTo(x1,y1);
    ctx.lineTo(x2,y2);
    ctx.stroke();
  }

  function clearCtx(ctx,c){
    if(c){
      ctx.fillStyle=c;
      ctx.fillRect(0,0,1000,100);
    }else{
      ctx.clearRect(0,0,1000,100);
    }
  }

  function mineCtx(){
    return document.getElementById('minecanvas').getContext('2d')
  }
  function diffCtx(){
    return document.getElementById('diffcanvas').getContext('2d')
  }
  function coinCtx(){
    return document.getElementById('coincanvas').getContext('2d')
  }

  // mining canvas

  var mineStat=[];
  var mnh=null, mxh=null;

  function clearMine(c){
    clearCtx(mineCtx(),c)
  }

  function addStat(fhs,fpr){
    if(fpr == undefined){ // Hits
      if(fhs) clearMine('rgba(0,255,0,1)');
      else    clearMine('rgba(255,0,0,1)');
      mineStat.push([fhs]);
    }
    // fHs
    else mineStat.push([fhs,fpr]);
    truncStat();
  }

  function truncStat(){
    while(mineStat.length>1000) mineStat.shift();
  }
  
  function drawSpeed(speed){
    var fhs,fpr;
    if(speed){
      var s=speed.split(' '); // 33750,Fhash/sec,(7.67,%)
      fhs=Number(s[0]),fpr=Number(s[2].replace('(',''));
      addStat(fhs,fpr);
    }
    mnh = null; mxh = null;
    for (var i=0;i<mineStat.length;i++) {
      if(mineStat[i][1] != undefined){
        if(mnh == null || mnh>mineStat[i][0]) mnh=mineStat[i][0];
        if(mxh == null || mxh<mineStat[i][0]) mxh=mineStat[i][0];
      }
    }
    var dist=Math.abs(mxh-mnh);
    clearMine(mineStat[mineStat.length-1][1] == undefined ? mineStat[mineStat.length-1][0] ? 'rgba(0,255,0,1)' : 'rgba(255,0,0,0)' : 'rgba(0,0,0,0.2)');
    var ctx=mineCtx();
    var l,t,c,pl=null,pt=null;
    for(var i=1,j=mineStat.length-1;i<=mineStat.length;i++,j--){
      l=1000-i;
      t=90 - (mineStat[j][1] == undefined ? 90 : ((80/dist)*(mineStat[j][0]-mnh)) );
      c=(255/100) * (mineStat[j][1] == undefined ? 100 : ((100/dist)*(mineStat[j][0]-mnh)) );
      var col = mineStat[j][1] == undefined ? mineStat[j][0] ? '#00aa00' : '#aa0000' : "rgb(255,"+Math.round((255*0.4)+(c*0.6))+",0)";
      drLine(ctx,pl==null?l:pl,mineStat[j][1] == undefined ? 100 : pt==null ? t : pt,l,t,3,col);
      if(mineStat[j][1] != undefined ){ pl=l; pt=t }
    }
    return [fhs,fpr];
  }

  // Difficulty Canvas

  var diffStat=[];
  var mndh=null, mxdh=null;

  function cleanDiff(){
    diffCtx().clearRect(0,0,2000,100);
  }

  function addDiff(diff){
    diffStat.push(Number(diff));
    truncDiff();
  }

  function truncDiff(){
    while(diffStat.length>500) diffStat.shift();
  }
  
  function drawDiff(diff){
    if(diff) addDiff(diff);
    for (var i=0;i<diffStat.length;i++) {
      if(diffStat[i] != undefined){
        var d=Number(diffStat[i]);
        if(mndh == null || mndh>d) mndh=d;
        if(mxdh == null || mxdh<d) mxdh=d;
      }
    }
    var dist=diffStat.length<2 || !(mxdh-mndh) ? 1 : Math.abs(mxdh-mndh);
    //console.log(dist+mndh);
    cleanDiff();
    var ctx=diffCtx();
    var l,t,c,d,pl=0,pt=null;
    for(var i=1,j=0;i<=diffStat.length;i++,j++){
      l=(i-1)*(2000/coinStat.length);
      d=(diffStat[j]-mndh);
      t=90 - (diffStat[j] == undefined ? 80 : ((80/dist)*d) );
      c=(255/100) * (diffStat[j] == undefined ? 0 : ((100/dist)*d) );
      var col = diffStat[j] == undefined ? 'red' : "rgba("+Math.round((255*0.2)+(c*0.4))+",0,255,0.8)";
      drLine(ctx,pl==null?l:pl,pt==null?t:pt,l,t,3,col);
      pl=l;
      pt=t;
    }
  }

  // Coinbase Canvas

  var coinStat=[];
  var mnch=null, mxch=null;

  function cleanCoin(){
    coinCtx().clearRect(0,0,2000,100);
  }

  function addCoin(time){
    coinStat.push(Number(time));
    truncCoin();
  }

  function truncCoin(){
    while(coinStat.length>500) coinStat.shift();
  }
  
  function timeCoin(time){
    if(coinStat.length) coinStat[coinStat.length-1]=time; else coinStat[0]=time;
    drawCoin();
  }

  function drawCoin(time){
    if(time!=undefined) addCoin(time);
    for (var i=0;i<coinStat.length;i++) {
      if(coinStat[i] != undefined){
        var d=Number(coinStat[i]);
        if(mnch == null || mnch>d) mnch=d;
        if(mxch == null || mxch<d) mxch=d;
      }
    }
    var dist=Math.abs(mxch-mnch);
    //console.log(dist+mnch);
    cleanCoin();
    var ctx=coinCtx();
    var l,t,c,d,pl=0,pt=null;
    for(var i=1,j=0;i<=coinStat.length;i++,j++){
      l=(i*(2000/coinStat.length));
      d=(coinStat[j]-mnch);
      t=90 - (coinStat[j] == undefined ? 0 : ((80/dist)*d) );
      c=(255/100) * (coinStat[j] == undefined ? 0 : ((100/dist)*d) );
      var col = coinStat[j] == undefined ? 'red' : "rgba(255,0,"+Math.round((255*0.2)+(c*0.4))+",0.8)";
      drLine(ctx,pl==null?l:pl,pt==null?t:pt,l,t,3,col);
      pl=l;
      pt=t;
    }
  }



