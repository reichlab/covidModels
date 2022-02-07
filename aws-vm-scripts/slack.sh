#!/bin/bash

#
# define slack communication functions
# - for simplicity we just use curl, which does not support formatted messages
# - requires these two environment variables to have been loaded (e.g., from ~/.env):
#     SLACK_API_TOKEN=xoxb-...
#     CHANNEL_ID=C...
#   = to load from ~/.env - per https://stackoverflow.com/questions/19331497/set-environment-variables-from-file-of-key-value-pairs
#     set -o allexport
#     source ~/.env
#     set +o allexport
#

slack_message() {
  # post a message to slack. args: $1: message to post. curl silent per https://stackoverflow.com/questions/32488162/curl-suppress-response-body
  echo "slack_message: $1"
  curl --silent --output /dev/null --show-error --fail -d "text=$1" -d "channel=${CHANNEL_ID}" -H "Authorization: Bearer ${SLACK_API_TOKEN}" -X POST https://slack.com/api/chat.postMessage
}

slack_upload() {
  # upload a file to slack. args: $1: file to upload. curl silent per https://stackoverflow.com/questions/32488162/curl-suppress-response-body
  FILE=$1
  if [ -f ${FILE} ]; then
    echo "slack_upload: ${FILE}"
    curl --silent --output /dev/null --show-error --fail -F file=@"${FILE}" -F "channels=${CHANNEL_ID}" -H "Authorization: Bearer ${SLACK_API_TOKEN}" https://slack.com/api/files.upload
  else
    echo >&2 "slack_upload: FILE not found: ${FILE}"
  fi
}
