#!/bin/bash

#
# A script that runs the weekly reports, messaging slack with progress and results.
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

slack_message "starting"

HUB_DIR="/data/covid19-forecast-hub"         # a fork
HUB_WEB_DIR="/data/covid19-forecast-hub-web" # not a fork
slack_message "updating forked HUB_DIR=${HUB_DIR} and HUB_WEB_DIR=${HUB_WEB_DIR}"

# sync fork w/upstream and then push to the fork b/c sometimes a PR will fail to be auto-merged, which we think is
# caused by an out-of-sync fork
cd "${HUB_DIR}"
git fetch upstream # pull down the latest source from original repo
git checkout master
git merge upstream/master # update fork from original repo to keep up with their changes
git push origin master    # sync with fork

cd ${HUB_WEB_DIR}
git pull

slack_message "deleting old files and running render_reports.R"
rm -f ${HUB_DIR}/code/reports/*.html

OUT_FILE=/tmp/run-weekly-reports-out.txt
cd ${HUB_DIR}/code/reports/
Rscript --vanilla render_reports.R >${OUT_FILE} 2>&1

if [ $? -eq 0 ]; then
  # script had no errors. copy the 54 reports into the covid19-forecast-hub-web/reports and then commit them and push
  # directly to master (no branch or PR)
  slack_message "render_reports.R OK; copying reports"
  cd ${HUB_WEB_DIR}
  cp -f ${HUB_DIR}/code/reports/*.html ${HUB_WEB_DIR}/reports
  git add reports/\*
  git commit -m "Latest reports"
  git push

  if [ $? -eq 0 ]; then
    # at this point the web site needs to be updated by running deploy-covidhub-site.sh, which is handled elsewhere. the
    # helper script covid19-forecast-hub-web/check_reports_deployment.py should now return False
    slack_message "push OK"
  else
    slack_message "push failed"
  fi
else
  # script had errors. upload just the log file
  slack_message "render_reports.R failed"
  slack_upload ${OUT_FILE}
fi

#
# done
#

do_shutdown
