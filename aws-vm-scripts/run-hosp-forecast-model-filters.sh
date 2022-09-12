#!/bin/bash

#
# A wrapper script to knit covid19-forecast-hub/code/reports/hospital-model-forecaster-filtering.Rmd and then share it
# by pushing it to a GitHub repo with Pages set up. Messages slack with progress and results.
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

# knit the file
slack_message "knitting the file"
cd "${HUB_DIR}"
Rscript -e "library(knitr); rmarkdown::render('code/reports/hospital-model-forecaster-filtering.Rmd')"

# save the html output file to the HUB_DIR root. NB: we do *not* update the web site by running the deploy GitHub Action
# as we do in run-weekly-reports.sh (see `gh workflow run blank.yml`) because it's not important enough to warrant the
# effort. we know a deploy happens in the evening anyway
OUT_FILE=${HUB_DIR}/code/reports/hospital-model-forecaster-filtering.html
slack_message "knit done, copying OUT_FILE=${OUT_FILE} to HUB_DIR=${HUB_DIR} root and pushing"
cd ${HUB_WEB_DIR}
cp -f ${OUT_FILE} ${HUB_WEB_DIR}
git add $(basename ${OUT_FILE})
git commit -m "Latest hospital model forecaster filtering file"
git push

slack_message "push done. The updated file will be at https://covid19forecasthub.org/$(basename ${OUT_FILE}) after the next web site deploy is run."

# done
do_shutdown
