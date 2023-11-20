#!/bin/bash

#
# A wrapper script to run the baseline model, messaging slack with progress and results.
#
# Environment variables (see README.md for details):
# - `SLACK_API_TOKEN`, `CHANNEL_ID` (required): used by slack.sh
# - `GH_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `GIT_CREDENTIALS` (required): used by load-env-vars.sh
# - `DRY_RUN` (optional): when set (to anything), stops git commit actions from happening (default is to do commits)
#

#
# load environment variables and then slack functions
#

echo "sourcing: load-env-vars.sh"
source "$(dirname "$0")/../docker-scripts/load-env-vars.sh"

echo "sourcing: slack.sh"
source "$(dirname "$0")/../aws-vm-scripts/slack.sh"

#
# start
#

slack_message "starting. id='$(id -u -n)', HOME='${HOME}', PWD='${PWD}'"

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
HUB_DIR="/data/covid19-forecast-hub" # a fork
BRANCH_NAME='baseline'
git -C ${HUB_DIR} branch --delete --force ${BRANCH_NAME} # delete local branch
git -C ${HUB_DIR} push origin --delete ${BRANCH_NAME}    # delete remote branch

slack_message "running make"
make -C "${COVID_MODELS_DIR}/weekly-submission" all >${OUT_FILE} 2>&1
MAKE_RESULT=$?

if [ ${MAKE_RESULT} -ne 0 ]; then
  # make had errors
  slack_message "make failed"
  slack_upload ${OUT_FILE}
  exit 1  # fail
fi

# make had no errors. find PDF and CSV files, add new csv file to new branch, and then upload log file and pdf files

slack_message "make OK; collecting PDF and CSV files"
CSV_DIR="${COVID_MODELS_DIR}/weekly-submission/forecasts/COVIDhub-baseline"

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

if [ "$NUM_PDF_DIRS" -ne 1 ]; then
  slack_message "PDF_DIR error: not exactly 1 PDF dir. PDF_DIRS=${PDF_DIRS}, NUM_PDF_DIRS=${NUM_PDF_DIRS}"
  slack_upload ${OUT_FILE}
  exit 1  # fail
fi

# found exactly one PDF_DIR
slack_message "PDF_DIR success: PDF_DIR=${PDF_DIR}"

if [ -n "${DRY_RUN+x}" ]; then
  PDF_FILES=$(find "${PDF_DIR}" -maxdepth 1 -mindepth 1 -type f)
  CSV_FILES=$(find "${CSV_DIR}" -maxdepth 1 -mindepth 1 -type f)
  slack_message "DRY_RUN set, exiting. PDF_FILES=${PDF_FILES}, CSV_FILES=${CSV_FILES}"
  exit 0  # success
fi

# PDF_DIR success + non-DRY_RUN: create and push branch with new CSV file. we first sync fork w/upstream and then push
# to the fork b/c sometimes a PR will fail to be auto-merged, which we think is caused by an out-of-sync fork
slack_message "updating forked HUB_DIR=${HUB_DIR}"
cd "${HUB_DIR}"
git fetch upstream # pull down the latest source from original repo
git checkout master
git merge upstream/master # update fork from original repo to keep up with their changes
git push origin master    # sync with fork

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
  exit 1  # fail
fi

# done with branch. upload PDFs, and optionally zipped CSV file (if push failed)
git checkout master
for PDF_FILE in "${PDF_DIR}"/*.pdf; do
  slack_upload "${PDF_FILE}"
done

if [ ${PUSH_RESULT} -ne 0 ]; then
  for CSV_FILE in "${CSV_DIR}"/*.csv; do
    ZIP_CSV_FILE=/tmp/$(basename "${CSV_FILE}").zip
    zip "${ZIP_CSV_FILE}" "${CSV_FILE}"
    slack_upload "${ZIP_CSV_FILE}"
  done
fi

#
# done
#

slack_message "done"
exit 0  # success
