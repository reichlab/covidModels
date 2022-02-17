#!/bin/bash

#
# A wrapper script to run the ensemble model, messaging slack with progress and results.
# - run as `ec2-user`, not root
#

# define utility function - used for normal and abnormal exits
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
# sync fork with upstream. note that we do not pull changes from the fork because we frankly don't need them; all we're
# concerned with is adding new files to a new branch and pushing them.
#

HUB_DIR="/data/covid19-forecast-hub" # a fork
slack_message "updating HUB_DIR=${HUB_DIR}. date=$(date), uname=$(uname -n)"

cd "${HUB_DIR}"
git fetch upstream        # pull down the latest source from original repo
git checkout master       # ensure I'm on local master
git merge upstream/master # update fork from original repo to keep up with their changes

# update covidData library
slack_message "updating covidData library. date=$(date), uname=$(uname -n)"
make -C /data/covidData/code/data-processing all

#
# build the model (this is the output from `make all -n`)
#

TODAY_DATE=$(date +'%Y-%m-%d') # e.g., 2022-02-17
OUT_FILE=/tmp/run-ensemble-out.txt
echo -n >${OUT_FILE} # truncate

slack_message "tagging inputs. date=$(date), uname=$(uname -n)"
git -C $(HUB_DIR) tag -a ${TODAY_DATE}-COVIDhub-ensemble -m "${TODAY_DATE}-COVIDhub-ensemble build inputs"
git -C $(HUB_DIR) push origin ${TODAY_DATE}-COVIDhub-ensemble

slack_message "running Rscript 1/6: build_trained_ensembles.R. date=$(date), uname=$(uname -n)"
Rscript build_trained_ensembles.R >>${OUT_FILE} 2>&1
if [ $? -ne 0 ]; then
  slack_message "script failed. exiting. date=$(date), uname=$(uname -n)"
  do_shutdown
fi

slack_message "running Rscript 2/6: build_4_week_ensembles.R. date=$(date), uname=$(uname -n)"
Rscript build_4_week_ensembles.R >>${OUT_FILE} 2>&1
if [ $? -ne 0 ]; then
  slack_message "script failed. exiting. date=$(date), uname=$(uname -n)"
  do_shutdown
fi

slack_message "running Rscript 3/6: build_ensembles.R. date=$(date), uname=$(uname -n)"
Rscript build_ensembles.R >>${OUT_FILE} 2>&1
if [ $? -ne 0 ]; then
  slack_message "script failed. exiting. date=$(date), uname=$(uname -n)"
  do_shutdown
fi

slack_message "running Rscript 4/6: plot_median_vs_trained_ensemble_forecasts.R. date=$(date), uname=$(uname -n)"
Rscript plot_median_vs_trained_ensemble_forecasts.R >>${OUT_FILE} 2>&1
if [ $? -ne 0 ]; then
  slack_message "script failed. exiting. date=$(date), uname=$(uname -n)"
  do_shutdown
fi

slack_message "running Rscript 5/6: fig-ensemble_weight.Rmd. date=$(date), uname=$(uname -n)"
Rscript -e "rmarkdown::render('fig-ensemble_weight.Rmd', output_file = paste0('plots/weight_reports/fig-ensemble_weight_', Sys.Date(),'.html'))" >>${OUT_FILE} 2>&1
if [ $? -ne 0 ]; then
  slack_message "script failed. exiting. date=$(date), uname=$(uname -n)"
  do_shutdown
fi

slack_message "running Rscript 6/6: plot_losses.R. date=$(date), uname=$(uname -n)"
Rscript plot_losses.R >>${OUT_FILE} 2>&1
if [ $? -ne 0 ]; then
  slack_message "script failed. date=$(date), uname=$(uname -n)"
  do_shutdown
fi

# main_pr
slack_message "creating main_pr. date=$(date), uname=$(uname -n)"
(git -C $(HUB_DIR) checkout main || git -C $(HUB_DIR) checkout -b main) &&
  cp forecasts/ensemble-metadata/${TODAY_DATE}* $(HUB_DIR)/ensemble-metadata/ &&
  cp forecasts/data-processed/COVIDhub-ensemble/${TODAY_DATE}-COVIDhub-ensemble.csv $(HUB_DIR)/data-processed/COVIDhub-ensemble/ &&
  cd $(HUB_DIR) &&
  git add -A &&
  git commit -m "${TODAY_DATE} ensemble" &&
  git push origin &&
  PR_URL=$(gh pr create --title "${TODAY_DATE} ensemble" --body "Main Ensemble, COVID19 Forecast Hub")

if [ $? -eq 0 ]; then
  slack_message "main_pr OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"
else
  slack_message "main_pr failed. date=$(date), uname=$(uname -a)"
  do_shutdown
fi

# trained_pr
slack_message "creating trained_pr. date=$(date), uname=$(uname -n)"
(git -C $(HUB_DIR) checkout trained || git -C $(HUB_DIR) checkout -b trained) &&
  cp forecasts/trained_ensemble-metadata/${TODAY_DATE}* $(HUB_DIR)/trained_ensemble-metadata/ &&
  cp forecasts/trained_ensemble-metadata/thetas.csv $(HUB_DIR)/trained_ensemble-metadata/thetas.csv &&
  cp forecasts/data-processed/COVIDhub-trained_ensemble/${TODAY_DATE}-COVIDhub-trained_ensemble.csv $(HUB_DIR)/data-processed/COVIDhub-trained_ensemble/ &&
  cd $(HUB_DIR) &&
  git add -A &&
  git commit -m "${TODAY_DATE} trained ensemble" &&
  git push origin &&
  PR_URL=$(gh pr create --title "${TODAY_DATE} trained ensemble" --body "Trained Ensemble, COVID19 Forecast Hub")

if [ $? -eq 0 ]; then
  slack_message "main_pr OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"
else
  slack_message "main_pr failed. date=$(date), uname=$(uname -a)"
  do_shutdown
fi

# 4wk_pr
slack_message "creating 4wk_pr. date=$(date), uname=$(uname -n)"
(git -C $(HUB_DIR) checkout 4wk || git -C $(HUB_DIR) checkout -b 4wk) &&
  cp forecasts/4_week_ensemble-metadata/${TODAY_DATE}* $(HUB_DIR)/4_week_ensemble-metadata/ &&
  cp forecasts/data-processed/COVIDhub-4_week_ensemble/${TODAY_DATE}-COVIDhub-4_week_ensemble.csv $(HUB_DIR)/data-processed/COVIDhub-4_week_ensemble/ &&
  cd $(HUB_DIR) &&
  git add -A &&
  git commit -m "${TODAY_DATE} 4 week ensemble" &&
  git push origin &&
  PR_URL=$(gh pr create --title "${TODAY_DATE} 4 week ensemble" --body "4 Week Ensemble, COVID19 Forecast Hub")

if [ $? -eq 0 ]; then
  slack_message "main_pr OK. PR_URL=${PR_URL}. date=$(date), uname=$(uname -a)"
else
  slack_message "main_pr failed. date=$(date), uname=$(uname -a)"
  do_shutdown
fi

#
# upload reports
# - relative to ../covidEnsembles/code/application/weekly-ensemble/plots/
#
slack_message "app PRs succeeded; uploading reports. date=$(date), uname=$(uname -n)"

# todo xx:
# COVIDhub-ensemble/${TODAY_DATE}/COVIDhub-ensemble-${TODAY_DATE}-cases.pdf
# COVIDhub-ensemble/${TODAY_DATE}/COVIDhub-ensemble-${TODAY_DATE}-deaths.pdf
# COVIDhub-ensemble/${TODAY_DATE}/COVIDhub-ensemble-${TODAY_DATE}-hospitalizations.pdf

# COVIDhub-4_week_ensemble/${TODAY_DATE}/COVIDhub-4_week_ensemble-${TODAY_DATE}-cases.pdf
# COVIDhub-4_week_ensemble/${TODAY_DATE}/COVIDhub-4_week_ensemble-${TODAY_DATE}-deaths.pdf
# COVIDhub-4_week_ensemble/${TODAY_DATE}/COVIDhub-4_week_ensemble-${TODAY_DATE}-hospitalizations.pdf

# COVIDhub-trained_ensemble/${TODAY_DATE}/COVIDhub-trained_ensemble-${TODAY_DATE}-cases.pdf
# COVIDhub-trained_ensemble/${TODAY_DATE}/COVIDhub-trained_ensemble-${TODAY_DATE}-deaths.pdf
# COVIDhub-trained_ensemble/${TODAY_DATE}/COVIDhub-trained_ensemble-${TODAY_DATE}-hospitalizations.pdf

# loss_plot_${TODAY_DATE}.pdf

# weight_reports/fig-ensemble_weight_${TODAY_DATE}.html

# ${TODAY_DATE}/forecast_comparison-${TODAY_DATE}-casess.pdf
# ${TODAY_DATE}/forecast_comparison-${TODAY_DATE}-deaths.pdf
# ${TODAY_DATE}/forecast_comparison-${TODAY_DATE}-hospitalizations.pdf
xx

#
# done!
#

do_shutdown
