#!/bin/bash

#
# testing script that runs against https://github.com/reichlabmachine/sandbox , primarily testing that
# `git config credential.helper store` is working right.
# - run as `ec2-user`, not root
#

# set environment variables - per https://stackoverflow.com/questions/19331497/set-environment-variables-from-file-of-key-value-pairs
set -o allexport
source ~/.env
set +o allexport

# load slack functions - per https://stackoverflow.com/questions/10822790/can-i-call-a-function-of-a-shell-script-from-another-shell-script/42101141#42101141
source $(dirname "$0")/slack.sh

# start
slack_message "$0 entered, editing file. date=$(date), uname=$(uname -a)"
cd /data/sandbox/
echo "$(date)" >>README.md
git add .
git commit -m "update"

slack_message "pushing. date=$(date), uname=$(uname -a)"
git push # where the trouble will be

slack_upload README.md
slack_message "done. date=$(date), uname=$(uname -a)"
