#!/bin/bash

#
# A script that deploys the weekly reports, either those created by run-weekly-reports.sh, or to deploy manually-
# created other changes. messaging slack with progress and results.
# - run as `ec2-user`, not root
#

# set environment variables - per https://stackoverflow.com/questions/19331497/set-environment-variables-from-file-of-key-value-pairs
set -o allexport
source ~/.env
set +o allexport

# load slack functions - per https://stackoverflow.com/questions/10822790/can-i-call-a-function-of-a-shell-script-from-another-shell-script/42101141#42101141
source $(dirname "$0")/slack.sh

# make `pipenv` and `bundle` available (respectively)
PATH=$PATH:~/.local/bin:~/bin

#
# start
#

slack_message "starting"

HUB_WEB_DIR="/data/covid19-forecast-hub-web" # not a fork
slack_message "updating HUB_WEB_DIR=${HUB_WEB_DIR}"

cd ${HUB_WEB_DIR}
git switch master
git pull

# run python scripts to generate community and reports files and then commit changes to the repo

slack_message "Updating community data"
pipenv run python3 update-community.py # _data/community.yml
git add _data/community.yml
git commit -m "update community"

slack_message "Updating reports data."
pipenv run python3 update-reports.py # reports/reports.json , eval-reports/reports.json
git add eval-reports/reports.json reports/reports.json
git commit -m "update report data"

slack_message "Pushing any changes."
git push

# remove old site and fetch clean repo. might be useful for a local build, likely not impacting CI Actions
rm -rf ./docs

# build the project into a local untracked "docs" directory on the master branch
slack_message "Building site"
bundle exec jekyll build -d docs

if [ $? -eq 0 ]; then
  slack_message "Site build OK"
else
  slack_message "Site built failed"
  do_shutdown
fi

# switch to netlify branch, bringing along untracked "docs" directory, then push to github to update the web site via
# netlify CI trigger
slack_message "Pushing to GitHub production branch"
git switch netlify
git pull
cp -r docs/* .
rm -rf docs/
rm -rf .sass-cache/
git add .

REPO=$(git config remote.origin.url)
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
HEAD_HASH=$(git rev-parse --verify HEAD) # latest commit hash
HEAD_HASH=${HEAD_HASH: -7}               # get the last 7 characters of hash
MSG="Auto deploy commit ${HEAD_HASH} to Netlify at $(date)"

git commit -am "${MSG}"

git push origin netlify
git switch master

#
# done
#

do_shutdown
