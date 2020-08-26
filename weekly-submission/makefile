# covidModels: make file for building COVIDhub-baseline model each week

# Define global variables
# This is a directory that is a local clone of reichlab/covid19-forecast-hub
HUB = ../../../../covid19-forecast-hub/

# data-processed folder within the covid19-forecast-hub repo
PROCESSED = $(HUB)data-processed/

# Define the full make, making plots and
all: baseline pull

# Get the latest forecast files from the hub repository
pull:
	git -C $(HUB) pull origin master

# Build the ensemble
baseline:
	Rscript fit_baseline_model.R

# TODO: commit, push to github, file pull request
