#!/bin/bash

#
# A wrapper script to run the baseline model, messaging slack with progress and results.
# - run as `ec2-user`, not root
#

# set environment variables - per https://stackoverflow.com/questions/19331497/set-environment-variables-from-file-of-key-value-pairs
set -o allexport
source ~/.env
set +o allexport

# load slack functions - per https://stackoverflow.com/questions/10822790/can-i-call-a-function-of-a-shell-script-from-another-shell-script/42101141#42101141
source $(dirname "$0")/slack.sh

#
# start
#

slack_message "$0 entered. date=$(date), uname=$(uname -a)"

HUB_DIR="/data/covid19-forecast-hub"
HUB_WEB_DIR="/data/covid19-forecast-hub-web"
slack_message "updating HUB_DIR=${HUB_DIR} and HUB_WEB_DIR=${HUB_WEB_DIR}. date=$(date), uname=$(uname -a)"

cd "${HUB_DIR}"
git fetch upstream       # pull down the latest source from original repo - https://github.com/reichlab/covid19-forecast-hub
git pull upstream master # update fork from original repo to keep up with their changes

cd ${HUB_WEB_DIR}
git fetch upstream
git pull upstream master

slack_message "NOT running render_reports.R (using html files from previous run). date=$(date), uname=$(uname -a)"
OUT_FILE=/tmp/run-weekly-reports-out.txt
cd ${HUB_DIR}/code/reports/
# Rscript --vanilla render_reports.R >${OUT_FILE} 2>&1
echo "not running script" >${OUT_FILE}

if [ $? -eq 0 ]; then
  # script had no errors. copy the 54 reports into the covid19-forecast-hub-web/reports . commit the reports and push.
  # we use a new branch which is used for a GitHub pull request
  NEW_BRANCH_NAME="weekly-reports-$(date +%Y%m%d)" # e.g., weekly-reports-20220207
  slack_message "render_reports.R OK; copying reports. NEW_BRANCH_NAME=${NEW_BRANCH_NAME}. date=$(date), uname=$(uname -a)"
  cd ${HUB_WEB_DIR}
  git checkout -b ${NEW_BRANCH_NAME}
  cp -f ${HUB_DIR}/code/reports/*.html ${HUB_WEB_DIR}/reports
  git add -Aa
  git commit -m "Latest reports"
  git push --set-upstream origin ${NEW_BRANCH_NAME}
  PUSH_RESULT=$?

  if [ $PUSH_RESULT -eq 0 ]; then
    # create the PR for the current branch
    slack_message "push OK. creating PR. date=$(date), uname=$(uname -a)"
    PR_URL=$(gh pr create --fill) #  e.g., https://github.com/reichlabmachine/sandbox/pull/1
    PR_RESULT=$?
    if [ PR_RESULT -eq 0 ]; then
      slack_message "PR creation OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"
    else
      slack_message "PR creation failed. date=$(date), uname=$(uname -a)"
    fi
  else
    slack_message "push failed. date=$(date), uname=$(uname -a)"
  fi

  slack_message "deleting local branch. date=$(date), uname=$(uname -a)"
  git checkout master              # change back to main branch
  git branch -D ${NEW_BRANCH_NAME} # remove weekly reports branch from local

  slack_message "delete done. date=$(date). repo=${ORIGIN_URL}. uname=$(uname -a)"

  # todo xx update the web site: run deploy GitHub Action - https://github.com/reichlab/covid19-forecast-hub-web#build-the-site-and-deploy-on-github-pages

else
  # script had errors. upload just the log file
  slack_message "render_reports.R failed. date=$(date), uname=$(uname -a)"
fi

#
# done!
#

slack_message "done. NOT shutting down. date=$(date), uname=$(uname -a)"
slack_upload ${OUT_FILE}
# sudo shutdown now -h
