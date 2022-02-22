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

slack_message "$0 entered. date=$(date), uname=$(uname -n)"

HUB_DIR="/data/covid19-forecast-hub"         # a fork
HUB_WEB_DIR="/data/covid19-forecast-hub-web" # not a fork
slack_message "updating HUB_DIR=${HUB_DIR} and HUB_WEB_DIR=${HUB_WEB_DIR}. date=$(date), uname=$(uname -n)"

# sync covid19-forecast-hub fork with upstream. note that we do not pull changes from the fork because we frankly don't
# need them; all we're concerned with is adding new files to a new branch and pushing them.
cd "${HUB_DIR}"
git fetch upstream        # pull down the latest source from original repo
git checkout master       # ensure I'm on local master
git merge upstream/master # update fork from original repo to keep up with their changes

cd ${HUB_WEB_DIR}
git pull

slack_message "deleting any old files and running render_reports.R. date=$(date), uname=$(uname -n)"
rm ${HUB_DIR}/code/reports/*.html

OUT_FILE=/tmp/run-weekly-reports-out.txt
cd ${HUB_DIR}/code/reports/
Rscript --vanilla render_reports.R >${OUT_FILE} 2>&1

if [ $? -eq 0 ]; then
  # script had no errors. copy the 54 reports into the covid19-forecast-hub-web/reports and then commit them and push
  # directly to master (no branch or PR)
  slack_message "render_reports.R OK; copying reports. date=$(date), uname=$(uname -n)"
  cd ${HUB_WEB_DIR}
  cp -f ${HUB_DIR}/code/reports/*.html ${HUB_WEB_DIR}/reports
  git add reports/\*
  git commit -m "Latest reports"
  git push

  if [ $? -eq 0 ]; then
    # update the web site by running the deploy GitHub Action - https://github.com/reichlab/covid19-forecast-hub/blob/master/.github/workflows/deploy-gh-pages.yml
    slack_message "push OK, running deploy workflow. date=$(date), uname=$(uname -n)"
    cd ${HUB_WEB_DIR}
    gh workflow run blank.yml
    if [ $? -eq 0 ]; then
      slack_message "deploy workflow started ok. please check the reports are up at: https://covid19forecasthub.org/reports/single_page.html and then send a message to #weekly-ensemble . date=$(date), uname=$(uname -n)"
    else
      slack_message "deploy workflow failed. date=$(date), uname=$(uname -n)"
    fi
  else
    slack_message "push failed. date=$(date), uname=$(uname -n)"
  fi
else
  # script had errors. upload just the log file
  slack_message "render_reports.R failed. date=$(date), uname=$(uname -n)"
fi

#
# done!
#

slack_message "done. shutting down. date=$(date), uname=$(uname -n)"
slack_upload ${OUT_FILE}
sudo shutdown now -h
