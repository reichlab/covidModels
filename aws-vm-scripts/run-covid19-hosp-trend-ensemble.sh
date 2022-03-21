#!/bin/bash

#
# A wrapper script to run the baseline model, messaging slack with progress and results.
# - run as `ec2-user`, not root
#

# define utility function - used for both normal and abnormal exits
do_shutdown() {
  slack_message "done. shutting down. date=$(date), uname=$(uname -n)"
  sudo shutdown now -h
}

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
# update covid-hosp-models and covidData repos, and sync covid19-forecast-hub fork with upstream
#

COVID_HOSP_MODELS_DIR="/data/covid-hosp-models"
WEEKLY_SUBMISSION_DIR=${COVID_HOSP_MODELS_DIR}/weekly-submission

git -C ${COVID_HOSP_MODELS_DIR} pull

# update covidData library
slack_message "updating covidData library. date=$(date), uname=$(uname -n)"

COVID_DATA_DIR="/data/covidData"
git -C ${COVID_DATA_DIR} pull
make -C ${COVID_DATA_DIR}/code/data-processing all

# sync covid19-forecast-hub fork with upstream. note that we do not pull changes from the fork because we frankly don't
# need them; all we're concerned with is adding new files to a new branch and pushing them.
HUB_DIR="/data/covid19-forecast-hub" # a fork
cd "${HUB_DIR}"
git fetch upstream # pull down the latest source from original repo
git checkout master
git merge upstream/master # update fork from original repo to keep up with their changes

#
# delete old branch
#

# todo xx: need to delete? name?
BRANCH_NAME='covid-hosp-models'
git branch --delete --force ${BRANCH_NAME} # delete local branch
git push origin --delete ${BRANCH_NAME}    # delete remote branch

#
# run the models
#

slack_message "running Rscript. date=$(date), uname=$(uname -n)"

OUT_FILE=/tmp/run-covid19-hosp-trend-ensemble-out.txt

cd ${COVID_HOSP_MODELS_DIR}
Rscript R/baseline.R >>${OUT_FILE} 2>&1

#
# process results
#

# to find the forecast file we first need the Monday date that the Rscript scripts used when creating files and dirs. we
# do so indirectly by looking for the new PDF file in ${WEEKLY_SUBMISSION_DIR}/baseline-plots/UMass-trends_ensemble
# (e.g., 2022-03-21-UMass-trends_ensemble.pdf) and then extracting the YYYY-MM-DD date from it. there should be exactly
# one file.
NEW_PDFS=$(git ls-files --other weekly-submission/baseline-plots/UMass-trends_ensemble/)
NUM_FILES=0
for PDF_FILE in $NEW_PDFS; do
  ((NUM_FILES++))
done

if [ $NUM_FILES -ne 1 ]; then
  slack_message "PDF_FILE error: not exactly 1 PDF file. NEW_PDFS=${NEW_PDFS}, NUM_FILES=${NUM_FILES}. date=$(date), uname=$(uname -n)"
  do_shutdown
fi

slack_message "PDF_FILE success: PDF_FILE=${PDF_FILE}. date=$(date), uname=$(uname -n)"
PDF_FILE_BASENAME=$(basename ${PDF_FILE}) # e.g., "2022-03-22-UMass-trends_ensemble.pdf"
MONDAY_DATE=${PDF_FILE_BASENAME:0:10}     # substring extraction per https://tldp.org/LDP/abs/html/string-manipulation.html

#
# submit forecast submission file from `weekly-submission/forecasts/UMass-trends_ensemble/` to the COVID-19 Forecast Hub as a PR
#

TODAY_DATE=$(date +'%Y-%m-%d') # e.g., 2022-02-17
CSV_FILE_NAME=${MONDAY_DATE}-UMass-trends_ensemble.csv
slack_message "creating PR. CSV_FILE_NAME=${CSV_FILE_NAME}. date=$(date), uname=$(uname -n)"
git -C ${HUB_DIR} checkout master &&
  git -C ${HUB_DIR} checkout -b ${BRANCH_NAME} &&
  cp ${WEEKLY_SUBMISSION_DIR}/forecasts/UMass-trends_ensemble/${CSV_FILE_NAME} ${HUB_DIR}/data-processed/UMass-trends_ensemble &&
  cd ${HUB_DIR} &&
  git add ${HUB_DIR}/data-processed/UMass-trends_ensemble/${CSV_FILE_NAME} &&
  git commit -m "${TODAY_DATE} Hosp Trend Ensemble" &&
  git push -u origin ${BRANCH_NAME} &&
  PR_URL=$(gh pr create --title "${TODAY_DATE} Hosp Trend Ensemble" --body "Hosp Trend Ensemble, COVID19 Forecast Hub")

if [ $? -eq 0 ]; then
  slack_message "PR OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"

  # todo xx correct to delete just local (but not `origin`) branch?:
  git branch --delete --force ${BRANCH_NAME} # delete local branch
else
  slack_message "PR failed. date=$(date), uname=$(uname -a)"
  do_shutdown
fi

#
# commit and push generated CSV files from all models and the PDF of plots from JUST the trends_ensemble model
#

slack_message "committing and pushing generated CSV and PDF files. date=$(date), uname=$(uname -n)"
cd ${COVID_HOSP_MODELS_DIR}
git add ${WEEKLY_SUBMISSION_DIR}/forecasts/
git add ${WEEKLY_SUBMISSION_DIR}/baseline-plots/UMass-trends_ensemble/
git commit -m "Hosp Trend Ensemble"
git push

#
# done!
#

do_shutdown
