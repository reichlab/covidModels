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

#
# update covidModels and covidData repos (the covid19-forecast-hub fork is updated post-make)
#

COVID_MODELS_DIR="/data/covidModels"

cd "${COVID_MODELS_DIR}"
git pull

cd /data/covidData/
git pull

#
# build the model, first cleaning up outputs from previous runs
# (@evan said: in general this will not be necessary. each week it creates a new set of plots and a submission file with
#  the date in the file name. but if you are running it multiple times within one week it'll probably be good to clear
#  things out)
#

OUT_FILE=/tmp/run-baseline-out.txt

slack_message "deleting any old files and running make. date=$(date), uname=$(uname -a)"
find ${COVID_MODELS_DIR}/weekly-submission/COVIDhub-baseline-plots -maxdepth 1 -mindepth 1 -type d -exec rm -rf '{}' \;
rm ${COVID_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline/*.csv
make -C "${COVID_MODELS_DIR}/weekly-submission" all >${OUT_FILE} 2>&1

#
# share results
#

if [ $? -eq 0 ]; then
  # make had no errors. add new csv file to new branch and then upload log file and pdf files
  slack_message "make OK; collecting PDF and CSV files. date=$(date), uname=$(uname -a)"

  # determine the Monday date used in the PDF folder, and PDF and CSV filenames, and then get the files for sharing/
  # uploading/pushing. for simplicity we look for the YYYY-MM-DD date in the PDF folder, rather than re-calculating the
  # Monday date, which is a little tricky and has already been done by `make`
  PDF_DIRS=$(find ${COVID_MODELS_DIR}/weekly-submission/COVIDhub-baseline-plots -maxdepth 1 -mindepth 1 -type d)
  NUM_PDF_DIRS=0
  for PDF_DIR in $PDF_DIRS; do
    ((NUM_PDF_DIRS++))
  done

  if [ $NUM_PDF_DIRS -ne 1 ]; then
    slack_message "PDF_DIR error: not exactly 1 PDF dir. NUM_PDF_DIRS=${NUM_PDF_DIRS}. date=$(date), uname=$(uname -a)"
  else
    slack_message "PDF_DIR success: PDF_DIR=${PDF_DIR}. date=$(date), uname=$(uname -a)"

    # create and push branch with new CSV file
    HUB_DIR="/data/covid19-forecast-hub"
    slack_message "updating HUB_DIR=${HUB_DIR}. date=$(date), uname=$(uname -a)"
    cd "${HUB_DIR}"
    git fetch upstream                            # pull down the latest source from original repo - https://github.com/reichlab/covid19-forecast-hub
    git pull upstream master                      # update fork from original repo to keep up with their changes

    MONDAY_DATE=$(basename ${PDF_DIR})            # e.g., 2022-01-31
    NEW_BRANCH_NAME="baseline-${MONDAY_DATE//-/}" # remove '-'. per https://tldp.org/LDP/abs/html/string-manipulation.html
    CSV_DIR="${COVID_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline"

    slack_message "creating branch and pushing. MONDAY_DATE=${MONDAY_DATE}, NEW_BRANCH_NAME=${NEW_BRANCH_NAME}. date=$(date), uname=$(uname -a)"
    git checkout -b ${NEW_BRANCH_NAME}
    cp ${CSV_DIR}/*.csv "${HUB_DIR}/data-processed/COVIDhub-baseline"
    git add -A
    git commit -m "baseline build, ${MONDAY_DATE}"
    git push --set-upstream origin ${NEW_BRANCH_NAME}
    PUSH_RESULT=$? # todo do in one expression

    if [ $PUSH_RESULT -eq 0 ]; then
      ORIGIN_URL=$(git config --get remote.origin.url) # e.g., https://github.com/reichlabmachine/covid19-forecast-hub.git
      ORIGIN_URL=${ORIGIN_URL::-4}                     # assumes original clone included ".git". todo one expression
      slack_message "push OK. CVS branch=${ORIGIN_URL}/tree/${NEW_BRANCH_NAME}. date=$(date), uname=$(uname -a)"
    else
      slack_message "push failed. date=$(date), uname=$(uname -a)"
    fi

    slack_message "deleting local branch. date=$(date), uname=$(uname -a)"
    git checkout master                              # change back to main branch
    git branch -D ${NEW_BRANCH_NAME}                 # remove baseline branch from local

    # done with branch. upload PDFs, and optionally zipped CSV file (if push failed)
    ORIGIN_URL=$(git config --get remote.origin.url) # e.g., https://github.com/reichlabmachine/covid19-forecast-hub.git
    ORIGIN_URL=${ORIGIN_URL::-4}                     # todo one expression
    slack_message "uploading log, PDFs, [CSVs]. date=$(date), uname=$(uname -a)"
    slack_upload ${OUT_FILE}

    for PDF_FILE in ${PDF_DIR}/*.pdf; do
      slack_upload ${PDF_FILE}
    done

    if [ $PUSH_RESULT -ne 0 ]; then
      for CSV_FILE in ${CSV_DIR}/*.csv; do
        # MONDAY_DATE=$(basename ${PDF_DIR}) # e.g., 2022-01-31
        # ZIP_CSV_FILE=/tmp/${CSV_FILE}.zip
        ZIP_CSV_FILE=/tmp/$(basename ${CSV_FILE}).zip
        zip ${ZIP_CSV_FILE} ${CSV_FILE}
        slack_upload ${ZIP_CSV_FILE}
      done
    fi

  fi
else
  # make had errors. upload just the log file
  slack_message "make failed. date=$(date), uname=$(uname -a)"
  slack_upload ${OUT_FILE}
fi

#
# done!
#

slack_message "done. shutting down. date=$(date), uname=$(uname -a)"
sudo shutdown now -h
