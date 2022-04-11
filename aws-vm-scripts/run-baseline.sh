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

slack_message "starting"

# update covidModels and covidData repos (the covid19-forecast-hub fork is updated post-make)
COVID_MODELS_DIR="/data/covidModels"
cd "${COVID_MODELS_DIR}"
git pull

# update covidData library
slack_message "updating covidData library"
COVID_DATA_DIR="/data/covidData"
git -C ${COVID_DATA_DIR} pull
make -C ${COVID_DATA_DIR}/code/data-processing all

#
# build the model, first cleaning up outputs from previous runs
# (@evan said: in general this will not be necessary. each week it creates a new set of plots and a submission file with
#  the date in the file name. but if you are running it multiple times within one week it'll probably be good to clear
#  things out)
#

OUT_FILE=/tmp/run-baseline-out.txt

slack_message "deleting old files"
find ${COVID_MODELS_DIR}/weekly-submission/COVIDhub-baseline-plots -maxdepth 1 -mindepth 1 -type d -exec rm -rf '{}' \;
rm -f ${COVID_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline/*.csv

slack_message "deleting old branch"
HUB_DIR="/data/covid19-forecast-hub"
BRANCH_NAME='baseline'
git -C ${HUB_DIR} branch --delete --force ${BRANCH_NAME} # delete local branch
git -C ${HUB_DIR} push origin --delete ${BRANCH_NAME}    # delete remote branch

slack_message "running make"
make -C "${COVID_MODELS_DIR}/weekly-submission" all >${OUT_FILE} 2>&1

#
# share results
#

if [ $? -eq 0 ]; then
  # make had no errors. add new csv file to new branch and then upload log file and pdf files
  slack_message "make OK; collecting PDF and CSV files"

  # find the PDF folder created by make. it is named for Monday's date, which is also used PDF and CSV filenames, e.g.,
  # make creates a file structure like so:
  #   weekly-submission/COVIDhub-baseline-plots/2022-04-04
  #   weekly-submission/COVIDhub-baseline-plots/2022-04-04/COVIDhub-baseline-2022-04-04-cases.pdf
  #   weekly-submission/COVIDhub-baseline-plots/2022-04-04/COVIDhub-baseline-2022-04-04-deaths.pdf
  #   weekly-submission/COVIDhub-baseline-plots/2022-04-04/COVIDhub-baseline-2022-04-04-hospitalizations.pdf
  PDF_DIRS=$(find ${COVID_MODELS_DIR}/weekly-submission/COVIDhub-baseline-plots -maxdepth 1 -mindepth 1 -type d)
  NUM_PDF_DIRS=0
  for PDF_DIR in $PDF_DIRS; do
    ((NUM_PDF_DIRS++))
  done

  if [ $NUM_PDF_DIRS -ne 1 ]; then
    slack_message "PDF_DIR error: not exactly 1 PDF dir. PDF_DIRS=${PDF_DIRS}, NUM_PDF_DIRS=${NUM_PDF_DIRS}"
  else
    slack_message "PDF_DIR success: PDF_DIR=${PDF_DIR}"

    # create and push branch with new CSV file. we could first sync w/upstream and then push to the fork, but this is
    # unnecessary for this script because `make all` gets the data it needs from the net and not the ${HUB_DIR}. note
    # that we may later decide to go ahead and sync in case other scripts that use this volume (at /data) need
    # up-to-date data, which is why we've kept the commands but commented them out. also note that we do not pull
    # changes from the fork because we frankly don't need them; all we're concerned with is adding new files to a new
    # branch and pushing them.
    cd "${HUB_DIR}"
    # git fetch upstream                         # pull down the latest source from original repo
    git checkout master
    # git merge upstream/master                  # update fork from original repo to keep up with their changes
    # git push origin master                     # sync with fork

    CSV_DIR="${COVID_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline"
    TODAY_DATE=$(date +'%Y-%m-%d') # e.g., 2022-02-17
    slack_message "creating branch and pushing. CSV_DIR=${CSV_DIR}"
    git checkout -b ${BRANCH_NAME}
    cp ${CSV_DIR}/*.csv ${HUB_DIR}/data-processed/COVIDhub-baseline
    git add data-processed/COVIDhub-baseline/\*
    git commit -m "baseline build, ${TODAY_DATE}"
    git push -u origin ${BRANCH_NAME}
    PUSH_RESULT=$?
    PR_URL=$(gh pr create --title "${TODAY_DATE} baseline" --body "baseline, COVID19 Forecast Hub")

    if [ $? -eq 0 ]; then
      slack_message "PR OK. PR_URL=${PR_URL}"
    else
      slack_message "PR failed"
      do_shutdown
    fi

    # done with branch. upload PDFs, and optionally zipped CSV file (if push failed)
    git checkout master
    slack_message "uploading log, PDFs, [CSVs]"
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
else
  # make had errors. upload just the log file
  slack_message "make failed"
  slack_upload ${OUT_FILE}
fi

#
# done!
#

slack_message "done. shutting down"
sudo shutdown now -h
