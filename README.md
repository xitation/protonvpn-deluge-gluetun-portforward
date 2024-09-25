# How to setup ProtonVPN + Port Forwarding, Deluge and Gluetun docker containers, to allow Deluge to work via a VPN correctly.

Hi! 

I recently decided it was time to ensure that [Deluge](https://deluge-torrent.org/) sent all it's traffic via a [Virtual Private Network (VPN)](https://en.wikipedia.org/wiki/Virtual_private_network) that supported [Port Forwarding](https://en.wikipedia.org/wiki/Port_forwarding). I decided on using [ProtonVPN](https://protonvpn.com/) as it now support [Port Forwarding](https://protonvpn.com/support/port-forwarding-manual-setup/).  I setup a bunch of [Docker containers](https://www.docker.com/resources/what-container/) including [Deluge LinuxServer.io container](https://docs.linuxserver.io/images/docker-deluge/) (I really like the LinuxServer.io containers, they are great) and also [Gluetun](https://github.com/qdm12/gluetun) to route all my traffic via [Wireguard](https://www.wireguard.com/), through ProtonVPN, with Port Forwarding enabled over ProtonVPN to allow Deluge to work correctly.

Big thanks [@soxfor](https://github.com/soxfor/qbittorrent-natmap) for inspiring me to make his idea work with Deluge instead of qBitorrent. 

Noting all this, this container runs a few scripts I've created. LinuxServer.io containers allow you to easily have them run script when they first start. This is important as the Port Forwards we get from ProtonVPN may change, and if that happens we need to ensure that Deluge has the correct listening port configured. API's to the rescue!

Deluge has an API (w00t!) we use this API to update the port that deluge listens on, thanks to [this deluge forum post](https://forum.deluge-torrent.org/viewtopic.php?t=56190) I was able to get this working with some docker tricks to pull the port issued by ProtonVPN from the Gluetun container. These 2 containers are reliant on one another, the Deluge container utilises the Gluetun containers Network Stack and Volumes.

Luckily the Deluge container already includes Cron, so with some minimal changes to Cron we can have my scripts run every 1 minute to ensure if the port changes, Deluge will get updated. Noting that, on first start-up of the containers, due to the order the LinuxServer.io customisations run, that the scripts will be unable to update the port until after Cron executes the job. This is because Deluge won't have actually started when the script runs.

This guide assume you have a working Docker environment, that that you somewhat know what you are doing with it.

# Proton VPN 
I stole most of this from here - https://gist.github.com/morningreis/eeda36e8bb07dcb750d77e9a744776e8 

## Preparation: Get Proton Configuration

Do the following to ensure you have setup a Wireguard VPN config with NAT-PMP enabled before proceeding with the Docker setup.

1.  Log into  [https://account.protonvpn.com/downloads](https://account.protonvpn.com/downloads)
2.  Scroll down half way to the Wireguard Configuration section
3.  Type in a name for the certificate you will generate, select  **Router**, and configure your VPN options (Malware/ad/tracker blocking, Moderate NAT, NAT-PMP, VPN Accelerator)
4.  You can hit the create button right under these settings and Proton will select the server closest to you, or you can manually select a server that you prefer.
5.  Hit create

You should get something similar to this:

```ini
[Interface]
# Key for Xi-Pir8-Demo
# Bouncing = 0
# NetShield = 0
# Moderate NAT = off
# NAT-PMP (Port Forwarding) = on
# VPN Accelerator = on
PrivateKey = 1zwqFv4PZP1/6a7msTzyLseLnv9U72O/jkyVd2Uiym8=
Address = 10.2.0.2/32
DNS = 10.2.0.1

[Peer]
# US-CA#33
PublicKey = 4v/dB/ha+PGL0jihNVlVj81NGAFh6VndO9s4giDZEUw=
AllowedIPs = 0.0.0.0/0
Endpoint = 185.230.126.18:51820
```

These values will go into the docker-compose file documented below.

# Docker Compose

Docker is great and all, but you know. What exact commands did I run to create the beast. In 10 minutes from now when I focus on some new shiny object I'm sure I'll have no idea. 
Welcome [Docker Compose.](https://docs.docker.com/compose/)
A yaml definition that describes exactly how to create a number of containers, as well as all the supporting aspects of a container, like networks, volumes, etc...

This is the compose file I use is below with some notes:

Things of Note:
 - The Deluge container mounts the volumes in the Gluetun container, my script requires a file on the Gluetun container to know the forwarded port, the script runs on the Deluge container as LinuxServer.io containers allow custom script execution.
 - ipv6 seems to break the Gluetun container at the moment, avoid letting the container get a v6 address or work out how to make the container prefer v6 over v4 on Alpine Linux. My 5 minutes on DuckDuckGo resulted in no simple solution so I gave up.
 - I got the Gluetun docker-compose config mostly from here - https://github.com/soxfor/qbittorrent-natmap/blob/main/docker-compose.yml
 -  Deluge is configured to exist within the Gluetun network context, which means the ports to access Deluge are configured on the Gluetun container.
 - You need to provide your Deluge Password to the Deluge container, as my script requires this to auth to the API. I suppose you could add a separate user to allow this to work, but I guess if you are the sort of person who is OK with storing a clear text password in a docker-compose file, you'll probably be rite mate. (maybe one day I'll do this, or even work out a way to use docker secrets, or setup Hashi Vault or something)

**IMORTANT NOTE:**
The <WIREGUARD_ADDRESSES> should be /28 subnet not /32 as defined by the ProtonVPN config file

```yaml
version: "2.1"
services:
  gluetun:
    # https://github.com/qdm12/gluetun
    image: ghcr.io/qdm12/gluetun:latest
    container_name: gluetun
    hostname: gluetun
    # line above must be uncommented to allow external containers to connect. See https://github.com/qdm12/gluetun/wiki/Connect-a-container-to-gluetun#external-container-to-gluetun
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - ./gluetun:/gluetun
      - ./gluetun/tmp:/tmp/gluetun/
      # If using ProtonVPN with OpenVPN, this path needs to be set to the downloaded .ovpn file
      # - /<yourpath>/<ovpn_config>.udp.ovpn:/gluetun/custom.conf:ro
    environment:
      # See https://github.com/qdm12/gluetun/wiki
      ## ProtonVPN Wireguard
      - VPN_SERVICE_PROVIDER=custom
      - VPN_TYPE=wireguard
      - VPN_ENDPOINT_IP=<Endpoint ip bit - from proton config file>
      - VPN_ENDPOINT_PORT=<Endpoint port bit - from proton config file>
      - WIREGUARD_PUBLIC_KEY=<PublicKey - from proton config file>
      - WIREGUARD_PRIVATE_KEY=<PrivateKey - from proton config file>
      - WIREGUARD_ADDRESSES=<Address - from proton config file>
      - VPN_PORT_FORWARDING=on
      - VPN_PORT_FORWARDING_PROVIDER=protonvpn
      ## ProtonVPN OpenVPN
      # - VPN_SERVICE_PROVIDER=custom
      # - VPN_TYPE=openvpn
      # - OPENVPN_CUSTOM_CONFIG=/gluetun/custom.conf
      # See https://protonvpn.com/support/port-forwarding-manual-setup/
      # - OPENVPN_USER=<username>+pmp
      # - OPENVPN_PASSWORD=
      # Timezone for accurate log times
      - TZ=Etc/UTC
      # Server list updater. See https://github.com/qdm12/gluetun/wiki/Updating-Servers#periodic-update
      - UPDATER_PERIOD=
      - UPDATER_VPN_SERVICE_PROVIDERS=
      # If QBITTORRENT_SERVER address is not related to VPN_IF_NAME (default: tun0) you'll need to set the variable below
      # - FIREWALL_OUTBOUND_SUBNETS=192.168.0.1/24
    ports:
      # - 8888:8888/tcp # HTTP proxy
      # - 8388:8388/tcp # Shadowsocks
      # - 8388:8388/udp # Shadowsocks
      - 8112:8112/tcp # Deluge ports, noting we use network_mode: "service:gluetun" on the deluge container
    networks:
      pir8-lan:
    labels:
      - "com.centurylinklabs.watchtower.enable=true" #I use watchtower
  deluge:
    image: lscr.io/linuxserver/deluge:amd64-latest
    container_name: deluge
    hostname: deluge
    environment:
      - PUID=1001 #change to your service account uid
      - PGID=1001 #change to your service account gid
      - TZ=Etc/UTC
      - DELUGE_LOGLEVEL=error #optional
      - DELUGE_PASSWORD=deluge #this is required for the curl scripts to connect to the Deluge API to update the Forwarded Port, it's not used for Deluge config at all though, only my script.
    volumes:
      - ./deluge_config:/config
      - ./downloads:/downloads
      - ./scripts:/custom-cont-init.d:ro #You can customaise linuxserver.io containers, who knew? :) - https://docs.linuxserver.io/general/container-customization/
    volumes_from: #this allows us to access the /tmp/gluetun/forwarded_port file that the gluetun container creates for us, my script uses this to work out the port we need to change via the Deluge API.
      - gluetun
    restart: unless-stopped
    healthcheck:
      test: curl --fail http://localhost:8112 || exit 1
      interval: 10s
      retries: 5
      start_period: 5s
      timeout: 10s
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  pir8-lan:
    name: containers
    external: true
    enable_ipv6: false #ipv6 breaks the gluetun container at the moment, so make sure it's not enabled
    driver: bridge
    driver_opts:
      com.docker.network.enable_ipv6: "false" #why configure it once, when you can do it twice?
```

# The Scripts

There are two (2).

 1. The script to setup the environment - *./scripts/setup.sh*
 2. The script that connect to the Deluge API and figures out the port forwarded port, and updates Deluge with this port - *./scripts/configure_port.sh*

These scripts are executed due to this awesome LinuxServer.io capability to modify their containers - https://docs.linuxserver.io/general/container-customization/ also because we mount a volume from ./scripts to /custom-cont-init.d within the Deluge container.

**IMORTANT NOTE:**
The scripts placed in ./scripts/*.sh must meet the following criteria or the container will ignore them on start-up:

 1. chmod +x ./scripts/* # The script must be Executable 
 2. chown -R root:root ./scripts #The Script should be owned by root
 3. Optional: When mounting the script in the container make it RO so that the container can't modify it

## The script to setup the environment - ./scripts/setup.sh

This script does the following in this exact order:

 1. Wait until /tmp/gluetun/forwarded_port exists on our Deluge container, this is mounted from the Gluetun container so if it's not done starting up, we need to wait for it to sort it's shit out so we can access this file. Deluge container start-up will pause until this is true. Noting this isn't really important for this script to work, but I figured noting we configure Cron, and it might execute the script fast, why not ensure everything is ready to go.
 2. Check if Curl is installed, if not install it.
 3. Check if the /etc/periodic/1min directory exists, if not create it
 4. Check if our script is in /etc/periodic/1min/configure_port.sh, it not copy it from /custom-cont-init.d/configure_port.sh into that location.
 5. Check if /etc/crontabs/root is configured to run all scripts in /etc/periodic/1min every 1 minute, if not add the entry that makes this work.
 6. That's it. She's done mate aka EOF

**Code:**

```bash
#!/bin/bash

# We require this file to exist, which means the gluetun container must have started before this one, so we wait until it's mounted into the deulue container
until ls /tmp/gluetun/forwarded_port
do
  echo "waiting for /tmp/gluetun/forwarded_port to be avaialble"
  sleep 2
done

# Setup some ENV things we use later, noting that FW Port file is mounted out of the gluetun container and if that doesn't happen this will fail to work
CRONTAB_FILE=/etc/crontabs/root

# Check if curl is installed, if not install it...
if [ ! -f /usr/bin/curl ]; then
  echo "**** installing curl ****"
  apk add --no-cache curl
fi

# Check if our cron dir exists if not create it...
if [ ! -d /etc/periodic/1min ]; then
  echo "**** creating /etc/periodic/1min directory ****"
  mkdir /etc/periodic/1min
fi

# Check if our script is copied over, if not copy it over...
if [ ! -f /etc/periodic/1min/configure_port.sh ]; then
  echo "**** copying $SCRIPT into /etc/periodic/1min directory ****"
  cp -af /custom-cont-init.d/configure_port.sh /etc/periodic/1min/
  chmod +x /custom-cont-init.d/configure_port.sh
fi

# check if we have the crontab entry in place, if not add it
isInFile=$(cat $CRONTAB_FILE | grep -c "1min")
if [ $isInFile -eq 0 ]; then
  echo "**** Setting up crontab entry to run setup.sh script ****"
  echo "*       *       *       *       *       run-parts /etc/periodic/1min" >> $CRONTAB_FILE
fi
```

## The script that connect to the Deluge API and figures out the port forwarded port, and updates Deluge with this port - *./scripts/configure_port.sh*

This script is the one that grabs the port from Gluetun and then updates the port in Deluge via it's API.
Docker is amazing, and allows you to easily inherit the volumes of other containers.
Gluetun is amazing and writes out the public ip (/tmp/gluetun/ip) and the port (/tmp/gluetun/forwarded_port) into files. Which makes my life pretty easy, I just turn those files into variables and then smash them into a curl command to configure Deluge. Then setup a Cronjob to do this every 60 seconds.

The script does the following in exactly this order:

 1. Wait to ensure the Deluge container can access /tmp/gluetun/forwarded_port mounted via the Gluetun container, we need this file to rip the port out into an envar and if it doens't exist the whole thing falls apart. So we pause until this exists.
 2. Setup an envar that reads the port number from /tmp/gluetun/forwarded_port
 3. Ensure Curl is installed, if not install it
 4. Sets up another envar that grabs an auth cookie from Deluge, authenticating with the Password you provided in docker-compose envars.
 5. Uses Curl to issue an API call to update the ports based on the envar we had stored previously
 6. Uses Curl to issue an API call to ensure that the "Random Port" checkbox is not checked

**Code:**

```bash
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
```
