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

#
# update covid-hosp-models and covidData repos (the covid19-forecast-hub fork is updated post-make)
#

COVID_HOSP_MODELS_DIR="/data/covid-hosp-models"
git -C ${COVID_HOSP_MODELS_DIR} pull

# update covidData library
slack_message "updating covidData library. date=$(date), uname=$(uname -n)"

COVID_DATA_DIR="/data/covidData"
git -C ${COVID_DATA_DIR} pull
make -C ${COVID_DATA_DIR}/code/data-processing all

#
# build the model, first cleaning up outputs from previous runs
#

slack_message "deleting old files and running Rscript. date=$(date), uname=$(uname -n)"

OUT_FILE=/tmp/run-covid19-hosp-trend-ensemble-out.txt

# todo xx
#find ${COVID_HOSP_MODELS_DIR}/weekly-submission/COVIDhub-baseline-plots -maxdepth 1 -mindepth 1 -type d -exec rm -rf '{}' \;
#rm -f ${COVID_HOSP_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline/*.csv

cd ${COVID_HOSP_MODELS_DIR}
Rscript R/baseline.R >>${OUT_FILE} 2>&1

#
# share results
#

# todo xx

# add new csv file to new branch and then upload log file and pdf files
slack_message "make OK; collecting PDF and CSV files. date=$(date), uname=$(uname -n)"

# determine the Monday date used in the PDF folder, and PDF and CSV filenames, and then get the files for sharing/
# uploading/pushing. for simplicity we look for the YYYY-MM-DD date in the PDF folder, rather than re-calculating the
# Monday date, which is a little tricky and has already been done by `make`
PDF_DIRS=$(find ${COVID_HOSP_MODELS_DIR}/weekly-submission/COVIDhub-baseline-plots -maxdepth 1 -mindepth 1 -type d)
NUM_PDF_DIRS=0
for PDF_DIR in $PDF_DIRS; do
  ((NUM_PDF_DIRS++))
done

if [ $NUM_PDF_DIRS -ne 1 ]; then
  slack_message "PDF_DIR error: not exactly 1 PDF dir. PDF_DIRS=${PDF_DIRS}, NUM_PDF_DIRS=${NUM_PDF_DIRS}. date=$(date), uname=$(uname -n)"
else
  slack_message "PDF_DIR success: PDF_DIR=${PDF_DIR}. date=$(date), uname=$(uname -n)"
  MONDAY_DATE=$(basename ${PDF_DIR}) # e.g., "2022-01-31"

  # create and push branch with new CSV file. we could first sync w/upstream and then push to the fork, but this is
  # unnecessary for this script because `make all` gets the data it needs from the net and not the ${HUB_DIR}. note
  # that we may later decide to go ahead and sync in case other scripts that use this volume (at /data) need
  # up-to-date data, which is why we've kept the commands but commented them out. also note that we do not pull
  # changes from the fork because we frankly don't need them; all we're concerned with is adding new files to a new
  # branch and pushing them.
  HUB_DIR="/data/covid19-forecast-hub"
  slack_message "NOT updating HUB_DIR=${HUB_DIR}. date=$(date), uname=$(uname -n)"
  cd "${HUB_DIR}"
  # git fetch upstream                         # pull down the latest source from original repo
  git checkout master
  # git merge upstream/master                  # update fork from original repo to keep up with their changes
  # git push origin master                     # sync with fork

  NEW_BRANCH_NAME="baseline-${MONDAY_DATE//-/}" # remove '-'. per https://tldp.org/LDP/abs/html/string-manipulation.html
  slack_message "deleting old branches. MONDAY_DATE=${MONDAY_DATE}, NEW_BRANCH_NAME=${NEW_BRANCH_NAME}. date=$(date), uname=$(uname -n)"
  git checkout master
  git branch --delete --force ${NEW_BRANCH_NAME} # delete local branch
  git push origin --delete ${NEW_BRANCH_NAME}    # delete remote branch

  CSV_DIR="${COVID_HOSP_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline"
  slack_message "creating branch and pushing. CSV_DIR=${CSV_DIR}. date=$(date), uname=$(uname -n)"
  git checkout -b ${NEW_BRANCH_NAME}
  cp ${CSV_DIR}/*.csv ${HUB_DIR}/data-processed/COVIDhub-baseline
  git add data-processed/COVIDhub-baseline/\*
  git commit -m "baseline build, ${MONDAY_DATE}"
  git push -u origin ${NEW_BRANCH_NAME}
  PUSH_RESULT=$?

  if [ $PUSH_RESULT -eq 0 ]; then
    ORIGIN_URL=$(git config --get remote.origin.url) # e.g., https://github.com/reichlabmachine/covid19-forecast-hub.git
    ORIGIN_URL=${ORIGIN_URL::-4}                     # assumes original clone included ".git"
    slack_message "push OK. CVS branch=${ORIGIN_URL}/tree/${NEW_BRANCH_NAME}. date=$(date), uname=$(uname -n)"
  else
    slack_message "push failed. date=$(date), uname=$(uname -n)"
  fi

  # done with branch. upload PDFs, and optionally zipped CSV file (if push failed)
  git checkout master
  slack_message "uploading log, PDFs, [CSVs]. date=$(date), uname=$(uname -n)"
  slack_upload ${OUT_FILE}

  for PDF_FILE in ${PDF_DIR}/*.pdf; do
    slack_upload ${PDF_FILE}
  done

  if [ $PUSH_RESULT -ne 0 ]; then
    for CSV_FILE in ${CSV_DIR}/*.csv; do
      ZIP_CSV_FILE=/tmp/$(basename ${CSV_FILE}).zip
      zip ${ZIP_CSV_FILE} ${CSV_FILE}
      slack_upload ${ZIP_CSV_FILE}
    done
  fi

fi

#
# done!
#

slack_message "done. shutting down. date=$(date), uname=$(uname -n)"
sudo shutdown now -h
