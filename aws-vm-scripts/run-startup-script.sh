#!/bin/bash

#
# This script is run when the instance starts up (via the instance's user data). It uses the value of the instance's
# tag with key "startup_script" to dispatch to the corresponding script in /data/covidModels/aws-vm-scripts . The value
# is the exact name of the script in that directory to run - no path, just script name. Does nothing if the script
# is not found, implementing a "noop" for interactive work.

echo "$0 entered. date=$(date), uname=$(uname -a)"

# look for the tag, get its value if present, get the corresponding script name, and run it if found

TOKEN=$(curl --silent --show-error -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
TAGS=$(curl --silent --show-error -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/tags/instance)
echo $TAGS

# set STARTUP_SCRIPT_VALUE
COVID_MODELS_DIR="/data/covidModels"
STARTUP_SCRIPT_TAG_NAME='startup_script'
for TAG_NAME in $TAGS; do
  TAG_VALUE=$(curl --silent --show-error -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/tags/instance/${TAG_NAME})
  echo "TAG_NAME=${TAG_NAME}, TAG_VALUE=${TAG_VALUE}"
  if [ $TAG_NAME = ${STARTUP_SCRIPT_TAG_NAME} ]; then
    STARTUP_SCRIPT_VALUE=${TAG_VALUE}
    break
  fi
done

# try to run the corresponding file
if [ -n ${STARTUP_SCRIPT_VALUE} ]; then
  STARTUP_SCRIPT="${COVID_MODELS_DIR}/aws-vm-scripts/${STARTUP_SCRIPT_VALUE}"
  if [ -f ${STARTUP_SCRIPT} ]; then
    echo "startup script found; starting. STARTUP_SCRIPT=${STARTUP_SCRIPT}. date=$(date), uname=$(uname -a)"
    source $STARTUP_SCRIPT
    echo "startup script done. date=$(date), uname=$(uname -a)"
  else
    echo "startup script not found. STARTUP_SCRIPT=${STARTUP_SCRIPT}. date=$(date), uname=$(uname -a)"
  fi
else
  echo "no STARTUP_SCRIPT_TAG_NAME found. date=$(date), uname=$(uname -a)"
fi

# done
echo "$0 done. date=$(date), uname=$(uname -a)"
