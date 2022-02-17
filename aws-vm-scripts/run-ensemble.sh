#!/bin/bash

#
# A wrapper script to run the ensemble model, messaging slack with progress and results.
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
# sync fork with upstream. note that we do not pull changes from the fork because we frankly don't need them; all we're
# concerned with is adding new files to a new branch and pushing them.
#

HUB_DIR="/data/covid19-forecast-hub" # a fork

cd "${HUB_DIR}"
git fetch upstream        # pull down the latest source from original repo
git checkout master       # ensure I'm on local master
git merge upstream/master # update fork from original repo to keep up with their changes

#
# build the model (this is the output from `make all -n`)
#

TODAY_DATE=$(shell date +'%Y-%m-%d')

OUT_FILE=/tmp/run-ensemble-out.txt
echo -n >${OUT_FILE}

git -C ${HUB} pull origin master
cd ../../../../covidData/code/data-processing
make all

git -C $(HUB) tag -a $(TODAY_DATE)-COVIDhub-ensemble -m "$(TODAY_DATE)-COVIDhub-ensemble build inputs"
git -C $(HUB) push origin $(TODAY_DATE)-COVIDhub-ensemble

Rscript build_trained_ensembles.R >${OUT_FILE} 2>&1
Rscript build_4_week_ensembles.R >${OUT_FILE} 2>&1
Rscript build_ensembles.R >${OUT_FILE} 2>&1
Rscript plot_median_vs_trained_ensemble_forecasts.R >${OUT_FILE} 2>&1
Rscript -e "rmarkdown::render('fig-ensemble_weight.Rmd', output_file = paste0('plots/weight_reports/fig-ensemble_weight_', Sys.Date(),'.html'))" >${OUT_FILE} 2>&1
Rscript plot_losses.R >${OUT_FILE} 2>&1

# main_pr
(git -C $(FHUB) checkout main || git -C $(FHUB) checkout -b main) &&
  cp forecasts/ensemble-metadata/$(TODAY_DATE)* $(FHUB)/ensemble-metadata/ &&
  cp forecasts/data-processed/COVIDhub-ensemble/$(TODAY_DATE)-COVIDhub-ensemble.csv $(FHUB)/data-processed/COVIDhub-ensemble/ &&
  cd $(FHUB) &&
  git add -A &&
  git commit -m "$(TODAY_DATE) ensemble" &&
  git push origin &&
  gh pr create --title "$(TODAY_DATE) ensemble" --body "Main Ensemble, COVID19 Forecast Hub"

# trained_pr
(git -C $(FHUB) checkout trained || git -C $(FHUB) checkout -b trained) &&
  cp forecasts/trained_ensemble-metadata/$(TODAY_DATE)* $(FHUB)/trained_ensemble-metadata/ &&
  cp forecasts/trained_ensemble-metadata/thetas.csv $(FHUB)/trained_ensemble-metadata/thetas.csv &&
  cp forecasts/data-processed/COVIDhub-trained_ensemble/$(TODAY_DATE)-COVIDhub-trained_ensemble.csv $(FHUB)/data-processed/COVIDhub-trained_ensemble/ &&
  cd $(FHUB) &&
  git add -A &&
  git commit -m "$(TODAY_DATE) trained ensemble" &&
  git push origin &&
  gh pr create --title "$(TODAY_DATE) trained ensemble" --body "Trained Ensemble, COVID19 Forecast Hub"

# 4wk_pr
(git -C $(FHUB) checkout 4wk || git -C $(FHUB) checkout -b 4wk) &&
  cp forecasts/4_week_ensemble-metadata/$(TODAY_DATE)* $(FHUB)/4_week_ensemble-metadata/ &&
  cp forecasts/data-processed/COVIDhub-4_week_ensemble/$(TODAY_DATE)-COVIDhub-4_week_ensemble.csv $(FHUB)/data-processed/COVIDhub-4_week_ensemble/ &&
  cd $(FHUB) &&
  git add -A &&
  git commit -m "$(TODAY_DATE) 4 week ensemble" &&
  git push origin &&
  gh pr create --title "$(TODAY_DATE) 4 week ensemble" --body "4 Week Ensemble, COVID19 Forecast Hub"

#
# done!
#

slack_message "done. shutting down. date=$(date), uname=$(uname -n)"
sudo shutdown now -h
