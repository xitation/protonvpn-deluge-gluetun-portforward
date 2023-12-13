#!/bin/bash

# We require this file to exist, which means the gluetun container must have started before this one, so we wait until it's mounted into the deulue container
until ls /tmp/gluetun/forwarded_port 
do
  echo "waiting for /tmp/gluetun/forwarded_port to be avaialble"
  sleep 2
done

# Setup some ENV things we use later, noting that FW Port file is mounted out of the gluetun container and if that doesn't happen this will fail to work
FORWARDED_PORT=`cat /tmp/gluetun/forwarded_port`

# Check if curl is installed, if not install it.
if [ ! -f /usr/bin/curl ]; then
  echo "**** installing curl ****"
  apk add --no-cache curl
fi

# taken from here - https://forum.deluge-torrent.org/viewtopic.php?t=56190 appears to work fine so didn't fuck with it too much
cookie=$(curl -v -H "Content-Type: application/json" -d '{"method": "auth.login", "params": ["'$DELUGE_PASSWORD'"], "id": 1}' http://localhost:8112/json 2>&1 | grep Cookie | cut -d':' -f2)
#curl -H "cookie: $cookie" -H "Content-Type: application/json" -d '{"method": "web.connect", "params": ["<HOSTID>"], "id": 1}' http://localhost:8112/json
curl -H "cookie: $cookie" -H "Content-Type: application/json" -d '{"method": "core.set_config", "params": [{"listen_ports": ['$FORWARDED_PORT','$FORWARDED_PORT']}], "id": 1}' http://localhost:8112/json
curl -H "cookie: $cookie" -H "Content-Type: application/json" -d '{"method": "core.set_config", "params": [{"random_port": false}], "id": 1}' http://localhost:8112/json
