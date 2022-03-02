#!/bin/bash

#
# A wrapper script to run the ensemble model, messaging slack with progress and results.
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

ENSEMBLES_DIR="/data/covidEnsembles"
WEEKLY_ENSEMBLE_DIR=${ENSEMBLES_DIR}/code/application/weekly-ensemble

slack_message "deleting any old files. date=$(date), uname=$(uname -n)"
rm -rf ${WEEKLY_ENSEMBLE_DIR}/forecasts/
rm -rf ${WEEKLY_ENSEMBLE_DIR}/plots/
rm -f ${WEEKLY_ENSEMBLE_DIR}/thetas-*

slack_message "deleting any old branches. date=$(date), uname=$(uname -n)"
BRANCHES="primary trained 4wk"
for BRANCH in ${BRANCHES}; do
  git checkout master
  git push origin --delete ${BRANCH}    # delete remote branch
  git fetch --prune origin              # delete remote tracking branch (prune removes any remote tracking branch in your local repository that points to a remote branch that has been deleted on the server)
  git branch --delete --force ${BRANCH} # delete local branch
done

#
# sync covid19-forecast-hub fork with upstream. note that we do not pull changes from the fork because we frankly don't
# need them; all we're concerned with is adding new files to a new branch and pushing them.
#

HUB_DIR="/data/covid19-forecast-hub" # a fork
slack_message "updating HUB_DIR=${HUB_DIR}. date=$(date), uname=$(uname -n)"

cd "${HUB_DIR}"
git fetch upstream # pull down the latest source from original repo
git checkout master
git merge upstream/master # update fork from original repo to keep up with their changes

# update covidEnsembles repo
cd ${ENSEMBLES_DIR}
git pull

# update covidData library
slack_message "updating covidData library. date=$(date), uname=$(uname -n)"
make -C /data/covidData/code/data-processing all

# tag build inputs
TODAY_DATE=$(date +'%Y-%m-%d') # e.g., 2022-02-17
OUT_FILE=/tmp/run-ensemble-out.txt
echo -n >${OUT_FILE} # truncate

slack_message "tagging inputs. date=$(date), uname=$(uname -n)"
git -C ${HUB_DIR} tag -a ${TODAY_DATE}-COVIDhub-ensemble -m "${TODAY_DATE}-COVIDhub-ensemble build inputs"
git -C ${HUB_DIR} push origin ${TODAY_DATE}-COVIDhub-ensemble

#
# build the model via a series of six R scripts
#

cd ${WEEKLY_ENSEMBLE_DIR}
mkdir -p plots/weight_reports

slack_message "running Rscript 1/6: build_trained_ensembles.R. date=$(date), uname=$(uname -n)"
Rscript build_trained_ensembles.R >>${OUT_FILE} 2>&1

slack_message "running Rscript 2/6: build_4_week_ensembles.R. date=$(date), uname=$(uname -n)"
Rscript build_4_week_ensembles.R >>${OUT_FILE} 2>&1

slack_message "running Rscript 3/6: build_ensembles.R. date=$(date), uname=$(uname -n)"
Rscript build_ensembles.R >>${OUT_FILE} 2>&1

slack_message "running Rscript 4/6: plot_median_vs_trained_ensemble_forecasts.R. date=$(date), uname=$(uname -n)"
Rscript plot_median_vs_trained_ensemble_forecasts.R >>${OUT_FILE} 2>&1

slack_message "running Rscript 5/6: fig-ensemble_weight.Rmd. date=$(date), uname=$(uname -n)"
Rscript -e "rmarkdown::render('fig-ensemble_weight.Rmd', output_file = paste0('plots/weight_reports/fig-ensemble_weight_', Sys.Date(),'.html'))" >>${OUT_FILE} 2>&1

slack_message "running Rscript 6/6: plot_losses.R. date=$(date), uname=$(uname -n)"
Rscript plot_losses.R >>${OUT_FILE} 2>&1

# primary_pr
slack_message "creating primary_pr. date=$(date), uname=$(uname -n)"
(git -C ${HUB_DIR} checkout primary || git -C ${HUB_DIR} checkout -b primary) &&
  cp ${WEEKLY_ENSEMBLE_DIR}/forecasts/ensemble-metadata/* ${HUB_DIR}/ensemble-metadata/ &&
  cp ${WEEKLY_ENSEMBLE_DIR}/forecasts/data-processed/COVIDhub-ensemble/* ${HUB_DIR}/data-processed/COVIDhub-ensemble/ &&
  cd ${HUB_DIR} &&
  git add -A &&
  git commit -m "${TODAY_DATE} ensemble" &&
  git push -u origin primary &&
  PR_URL=$(gh pr create --title "${TODAY_DATE} ensemble" --body "Primary Ensemble, COVID19 Forecast Hub")

if [ $? -eq 0 ]; then
  slack_message "primary_pr OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"
else
  slack_message "primary_pr failed. date=$(date), uname=$(uname -a)"
  do_shutdown
fi

# trained_pr
slack_message "creating trained_pr. date=$(date), uname=$(uname -n)"
(git -C ${HUB_DIR} checkout trained || git -C ${HUB_DIR} checkout -b trained) &&
  cp ${WEEKLY_ENSEMBLE_DIR}/forecasts/trained_ensemble-metadata/* ${HUB_DIR}/trained_ensemble-metadata/ &&
  cp ${WEEKLY_ENSEMBLE_DIR}/forecasts/data-processed/COVIDhub-trained_ensemble/* ${HUB_DIR}/data-processed/COVIDhub-trained_ensemble/ &&
  cd ${HUB_DIR} &&
  git add -A &&
  git commit -m "${TODAY_DATE} trained ensemble" &&
  git push -u origin trained &&
  PR_URL=$(gh pr create --title "${TODAY_DATE} trained ensemble" --body "Trained Ensemble, COVID19 Forecast Hub")

if [ $? -eq 0 ]; then
  slack_message "trained_pr OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"
else
  slack_message "trained_pr failed. date=$(date), uname=$(uname -a)"
  do_shutdown
fi

# 4wk_pr
slack_message "creating 4wk_pr. date=$(date), uname=$(uname -n)"
(git -C ${HUB_DIR} checkout 4wk || git -C ${HUB_DIR} checkout -b 4wk) &&
  cp ${WEEKLY_ENSEMBLE_DIR}/forecasts/4_week_ensemble-metadata/* ${HUB_DIR}/4_week_ensemble-metadata/ &&
  cp ${WEEKLY_ENSEMBLE_DIR}/forecasts/data-processed/COVIDhub-4_week_ensemble/* ${HUB_DIR}/data-processed/COVIDhub-4_week_ensemble/ &&
  cd ${HUB_DIR} &&
  git add -A &&
  git commit -m "${TODAY_DATE} 4 week ensemble" &&
  git push -u origin 4wk &&
  PR_URL=$(gh pr create --title "${TODAY_DATE} 4 week ensemble" --body "4 Week Ensemble, COVID19 Forecast Hub")

if [ $? -eq 0 ]; then
  slack_message "4wk_pr OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"
else
  slack_message "4wk_pr failed. date=$(date), uname=$(uname -a)"
  do_shutdown
fi

#
# upload reports
#

slack_message "app PRs succeeded; uploading reports. date=$(date), uname=$(uname -n)"

# to find reports we first need the Monday date that the Rscript scripts used when creating files and dirs. we do so
# indirectly by looking for the file loss_plot_${TODAY_DATE}.pdf and then extracting the YYYY-MM-DD date from it. there
# should be exactly one file.

LOSS_PLOT_PDFS=$(find ${WEEKLY_ENSEMBLE_DIR}/plots/loss_plot_*.pdf)
NUM_FILES=0
for PDF_FILE in $LOSS_PLOT_PDFS; do
  ((NUM_FILES++))
done

if [ $NUM_FILES -ne 1 ]; then
  slack_message "PDF_FILE error: not exactly 1 loss plot PDF file. LOSS_PLOT_PDFS=${LOSS_PLOT_PDFS}, NUM_FILES=${NUM_FILES}. date=$(date), uname=$(uname -n)"
else
  slack_message "PDF_FILE success: PDF_FILE=${PDF_FILE}. date=$(date), uname=$(uname -n)"
  PDF_FILE_BASENAME=$(basename ${PDF_FILE}) # e.g., "loss_plot_2022-02-21.pdf"
  MONDAY_DATE=${PDF_FILE_BASENAME:10:10}    # substring extraction per https://tldp.org/LDP/abs/html/string-manipulation.html

  # upload the files
  cd ${WEEKLY_ENSEMBLE_DIR}/plots
  UPLOAD_FILES="COVIDhub-4_week_ensemble/${MONDAY_DATE}/*.pdf COVIDhub-ensemble/${MONDAY_DATE}/*.pdf COVIDhub-trained_ensemble/${MONDAY_DATE}/*.pdf weight_reports/fig-ensemble_weight_${TODAY_DATE}.html loss_plot_${MONDAY_DATE}.pdf ${MONDAY_DATE}/*.pdf "
  for UPLOAD_FILE in ${UPLOAD_FILES}; do
    slack_upload ${UPLOAD_FILE}
  done
fi

#
# done!
#

do_shutdown
