#!/bin/bash

set -e
set -o pipefail

MIX_ENV=test

cd farmbot_telemetry

echo "######### farmbot_telemetry"
cd ../farmbot_telemetry
mix deps.get --all
mix format
# rm -rf deps; rm -rf _build/
mix coveralls.html
# rm -f *.coverdata
MIX_ENV=test mix compile

echo "######### farmbot_celery_script"
cd ../farmbot_celery_script
mix deps.get --all
mix format
# rm -rf deps; rm -rf _build/
mix coveralls.html
# rm -f *.coverdata
MIX_ENV=test mix compile

echo "######### farmbot_firmware"
cd ../farmbot_firmware
mix deps.get --all
mix format
# rm -rf deps; rm -rf _build/
mix coveralls.html
# rm -f *.coverdata
MIX_ENV=test mix compile

echo "######### farmbot_core"
cd ../farmbot_core
# rm -rf deps; rm -rf _build/
mix deps.get --all
mix format
mix coveralls.html
# rm -f *.coverdata
MIX_ENV=test mix compile

echo "######### farmbot_ext"
cd ../farmbot_ext
mix deps.get --all
mix format
# rm -rf deps; rm -rf _build/
mix coveralls.html
# rm -f *.coverdata
MIX_ENV=test mix compile

echo "######### farmbot_os"
cd ../farmbot_os
mix deps.get --all
mix format
# rm -rf deps; rm -rf _build/
mix coveralls.html
# rm -f *.coverdata
MIX_ENV=test mix compile

cd ..
cd farmbot_os

echo "######### Build RPI3 FW"

# rm -rf deps; rm -rf _build/
MIX_TARGET=rpi3 MIX_ENV=prod mix deps.get
MIX_TARGET=rpi3 MIX_ENV=prod mix compile --force
MIX_TARGET=rpi3 MIX_ENV=prod mix firmware

echo "######### Build RPI0 FW"
MIX_TARGET=rpi MIX_ENV=prod mix deps.get
# rm -rf deps; rm -rf _build/
MIX_TARGET=rpi MIX_ENV=prod mix compile --force
MIX_TARGET=rpi MIX_ENV=prod mix firmware
