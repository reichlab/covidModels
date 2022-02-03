#!/bin/bash

#
# A wrapper script to run the baseline model, messaging slack with progress and results.
# - run as `ec2-user`, not root
#

#
# define slack communication functions
# - note: for simplicity we just use curl, which does not support formatted messages
# - credentials: requires a ~/.env file that contains two variables:
#   SLACK_API_TOKEN=xoxb-...
#   CHANNEL_ID=C...
#

# per https://stackoverflow.com/questions/19331497/set-environment-variables-from-file-of-key-value-pairs
set -o allexport
source ~/.env
set +o allexport

slack_message() {
  # post a message to slack. args: $1: message to post
  echo "slack_message: $1"
  curl -d "text=$1" -d "channel=${CHANNEL_ID}" -H "Authorization: Bearer ${SLACK_API_TOKEN}" -X POST https://slack.com/api/chat.postMessage
}

slack_upload() {
  # upload a file to slack. args: $1: file to upload
  FILE=$1
  if [ -f ${FILE} ]; then
    echo "slack_upload: ${FILE}"
    curl -F file=@"${FILE}" -F "channels=${CHANNEL_ID}" -H "Authorization: Bearer ${SLACK_API_TOKEN}" https://slack.com/api/files.upload
  else
    echo >&2 "slack_upload: FILE not found: ${FILE}"
  fi
}

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
    cd "${HUB_DIR}"
    git fetch upstream # pull down the latest source from original repo - https://github.com/reichlab/covid19-forecast-hub
    git pull upstream master  # update fork from original repo to keep up with their changes

    MONDAY_DATE=$(basename ${PDF_DIR})            # e.g., 2022-01-31
    NEW_BRANCH_NAME="baseline-${MONDAY_DATE//-/}" # remove '-'. per https://tldp.org/LDP/abs/html/string-manipulation.html
    CSV_DIR="${COVID_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline"

    slack_message "creating branch and pushing. MONDAY_DATE=${MONDAY_DATE}, NEW_BRANCH_NAME=${NEW_BRANCH_NAME}. date=$(date), uname=$(uname -a)"
    git checkout -b ${NEW_BRANCH_NAME}
    cp ${CSV_DIR}/*.csv "${HUB_DIR}/data-processed/COVIDhub-baseline"
    git add -A
    git commit -m "baseline build, ${MONDAY_DATE}"
    git push --set-upstream origin ${NEW_BRANCH_NAME}

    slack_message "deleting local branch. date=$(date), uname=$(uname -a)"
    git checkout master                              # change back to main branch
    git branch -D ${NEW_BRANCH_NAME}                 # remove baseline branch from local

    # done with branch. report success and upload PDFs
    ORIGIN_URL=$(git config --get remote.origin.url) # e.g., https://github.com/reichlabmachine/covid19-forecast-hub.git
    ORIGIN_URL=${ORIGIN_URL::-4}                     # todo do in one expression :-)

    slack_message "uploading log and PDFs. date=$(date). CVS branch=${ORIGIN_URL}/tree/${NEW_BRANCH_NAME}. uname=$(uname -a)"
    slack_upload ${OUT_FILE}
    for PDF_FILE in ${PDF_DIR}/*.pdf; do
      slack_upload ${PDF_FILE}
    done
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
