#!/bin/bash

#
# This is a small helper script that processes the environment variables documented in README.md, saving the results
# into the corresponding files under ${HOME}.
#

# write incoming environment variables into three files. see README.md for details

# verify all vars passed in
if [ -z ${SLACK_API_TOKEN+x} ] || [ -z ${CHANNEL_ID+x} ] || [ -z ${GH_TOKEN+x} ] || [ -z ${GIT_USER_NAME+x} ] || [ -z ${GIT_USER_EMAIL+x} ] || [ -z ${GIT_CREDENTIALS+x} ]; then
  echo "one or more required environment variables were unset: SLACK_API_TOKEN='${SLACK_API_TOKEN}', CHANNEL_ID='${CHANNEL_ID}', GH_TOKEN='${GH_TOKEN}', GIT_USER_NAME='${GIT_USER_NAME}', GIT_USER_EMAIL='${GIT_USER_EMAIL}', GIT_CREDENTIALS='${GIT_CREDENTIALS}'"
  exit 1 # failure
else
  echo "found all required environment variables"
fi

# file 1/3: ~/.env
ENV_FILE_NAME="${HOME}/.env"
echo "SLACK_API_TOKEN=${SLACK_API_TOKEN}" >"${ENV_FILE_NAME}" # NB: overwrites!
echo "CHANNEL_ID=${CHANNEL_ID}" >>"${ENV_FILE_NAME}"
echo "GH_TOKEN=${GH_TOKEN}" >>"${ENV_FILE_NAME}"

# file 2/3: ~/.git-credentials
echo "${GIT_CREDENTIALS}" >"${HOME}/.git-credentials"

# file 3/3: ~/.gitconfig
git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"
git config --global credential.helper store

# load environment variables - per https://stackoverflow.com/questions/19331497/set-environment-variables-from-file-of-key-value-pairs
set -o allexport
source "${ENV_FILE_NAME}"
set +o allexport
