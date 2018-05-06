FCC Wallet script
-- Development Version --

Copy all files into the same wallet directory as the normal version. (don't forget the extra image file)


The trusted.nodes file is for now a fix to get your wallet started beyond the nodelist request fails what seems to occure at some places. We are still fixing this particulare issue.


The Start_Wallet_[PORT]\_[OS] start-scripts can be copied to other start-file names, in where you change the internal wallet port you start your wallet with. This way you can start more than one wallet-miner on multi-core systems, while you use the same wallet.fcc file and scripts in the same directory. You can also omit the port (like in the Start_Wallet_[OS] files), and set it in the wallet.port file as a default port. When not present, it uses default 5115. This way the wallet-miner can only be mining on a single core.
