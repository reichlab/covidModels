#!/bin/bash

#
# testing script that runs against https://github.com/reichlabmachine/sandbox , primarily testing that
# `git config credential.helper store` is working right.
# - run as `ec2-user`, not root
#

set -o allexport
source ~/.env
set +o allexport

slack_message() {
  # post a message to slack. args: $1: message to post
  echo "slack_message: $1"
  curl -d "text=$1" -d "channel=${CHANNEL_ID}" -H "Authorization: Bearer ${SLACK_API_TOKEN}" -X POST https://slack.com/api/chat.postMessage
}

slack_message "$0 entered, editing file. date=$(date), uname=$(uname -a)"
cd /data/sandbox/
echo "$(date)" >>README.md
git add .
git commit -m "update"

slack_message "pushing. date=$(date), uname=$(uname -a)"
git push # where the trouble will be

slack_message "done. date=$(date), uname=$(uname -a)"
