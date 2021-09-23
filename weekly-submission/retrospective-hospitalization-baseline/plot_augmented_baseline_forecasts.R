library(tidyverse)
library(zeallot)
library(covidEnsembles)
library(covidData)
library(here)
setwd(here())

# Location of where component model submissions can be found
submissions_root <- "../covid19-forecast-hub/data-processed/"

# Where we want to save the plots
plots_root <- "weekly-submission/retrospective-hospitalization-baseline/forecast-plots/"
if (!dir.exists(plots_root)) {
  dir.create(plots_root, recursive = TRUE)
}

forecast_dates <- seq.Date(
  from = as.Date("2020-12-05") + 2,
  to = as.Date("2021-09-18") + 2,
  by = 7)

for (forecast_date in as.character(forecast_dates)) {
  covidEnsembles::plot_forecasts_single_model(
    submissions_root = submissions_root,
    plots_root = plots_root,
    forecast_date = as.Date(forecast_date),
    model_abbrs = "COVIDhub-baseline",
    target_variables = "hospitalizations"
  )
}
