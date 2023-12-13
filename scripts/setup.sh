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
