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

# start
slack_message "starting"

# sync covid19-forecast-hub fork with upstream
slack_message "updating covid19-forecast-hub fork"
HUB_DIR="/data/covid19-forecast-hub" # a fork
cd "${HUB_DIR}"
git fetch upstream # pull down the latest source from original repo
git checkout master
git merge upstream/master # update fork from original repo to keep up with their changes

# knit the file
slack_message "knitting the file"
Rscript -e "library(knitr); rmarkdown::render('code/reports/hospital-model-forecaster-filtering.Rmd')"

# publish output file. todo xx add to GitHub Pages repo, commit, push, print message (link to page), etc.
# for now simply upload the file
OUT_FILE=${HUB_DIR}/code/reports/hospital-model-forecaster-filtering.html
slack_message "knit done"
slack_upload ${OUT_FILE}

# done
slack_message "done. shutting down"
sudo shutdown now -h
