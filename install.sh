#!/bin/bash

# MacOS
brew install lua
brew install luarocks
luarocks install luasocket
luarocks install busted

# Ubuntu
sudo apt-get install lua5.1
sudo apt-get install luarocks
sudo luarocks install luasocket
sudo luarocks install busted

# Sobre timeout não respeitado: Instalar luasocket com luarocks resolveu o
# problema para 5.1 e 5.2.

# Source
export LUA_PREFIX="/tmp/lua"
mkdir -p $LUA_PREFIX

cd $LUA_PREFIX
#wget http://www.lua.org/ftp/lua-5.2.3.tar.gz
wget http://www.lua.org/ftp/lua-5.1.4.tar.gz
#tar xzvf lua-5.2.3.tar.gz
tar xzvf lua-5.1.4.tar.gz
#cd lua-5.2.3
cd lua-5.1.4
make linux

cd $LUA_PREFIX
wget https://github.com/diegonehab/luasocket/archive/v3.0-rc1.tar.gz
tar xzvf v3.0-rc1.tar.gz
cd luasocket-3.0-rc1
#cp -a $LUA_PREFIX/lua-5.2.3/src/* src/
cp -a $LUA_PREFIX/lua-5.1.4/src/* src/
make

cd src
mkdir socket mime
cp -a mime.so.1.0.3 mime/core.so
cp -a socket.so.3.0-rc1 socket/core.so

echo
echo
pwd
echo "socket = require('socket')"
echo
echo

./lua

# Versão
sudo update-alternatives --set lua-compiler /usr/bin/luac5.2
sudo update-alternatives --set lua-interpreter /usr/bin/lua5.2
sudo update-alternatives --set lua-compiler /usr/bin/luac5.1
sudo update-alternatives --set lua-interpreter /usr/bin/lua5.1
