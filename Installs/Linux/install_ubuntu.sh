#!/bin/bash

os=$(getconf LONG_BIT)
echo Operating System is $os bit

exists() {
  command -v "$1" >/dev/null 2>&1
}
installperl() {
  if [ "os" == "64" ]; then
    echo Installing Perl v5.26.1 ..
    tar xzf ActivePerl-5.26.1.2601-x86_64-linux-glibc-2.15-404865.tar.gz
    cd ActivePerl-5.26.1.2601-x86_64-linux-glibc-2.15-404865
    ./install.sh --prefix /perl --license-accepted --no-update-check --no-komodo
    if [ -e /usr/bin/perl ]; then
      rm /usr/bin/perl
    fi
    cd ..
    ln /perl/bin/perl-dynamic /usr/bin/perl
    (echo y;echo o conf prerequisites_policy follow;echo o conf commit)|cpan
  else
    apt --force-yes install perl
  fi
  pv=$(perl -e "print $^V")
  echo Perl is installed \(version $pv\)
}

cu=$(id -un)
if [ "$cu" != "root" ]; then
  echo Please run this script as 'root'
  exit 1
fi

echo Installing compiler ..
apt --force-yes update
apt --force-yes install gcc
apt --force-yes install make

echo Installing Perl ..
if exists perl; then
  pv=$(perl -e "print $^V")
  echo Perl is already installed \(version $pv\)
  if [ "os" == "64" ]; then
    if [ "$pv" \< "v5.26.1" ]; then
      echo Newer version of Perl \(v5.26.1\) available!
      read -r -p "Install newer version? [y/N] " response
      if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
      then
        installperl
      fi
    fi
  fi
else
  installperl
fi
echo Installing Zlib ..
tar xzf zlib_1.2.8.dfsg.orig.tar.gz
cd zlib-1.2.8
./configure
make
make install
cd ..
echo Installing dependencies for Perl ..
apt-get ==force-yes install cpanminus #Toegevoegd, je weet maar nooit wie cpan heeft :p
apt-get --force-yes install libnet-ssleay-perl libssl-dev #Deze twee libs zijn nodig voor IO::Socket::SSL
cpan install JSON Crypt::Ed25519 URL::Encode Browser::Open Gzip::Faster IO::Socket:SSL Digest::SHA1 Crypt::CBC #IO::Socket::SSL Digest::SHA1 Crypt::CBC worden bij deze ook geïnstalleerd
perl install.cgi
echo Installation completed!
