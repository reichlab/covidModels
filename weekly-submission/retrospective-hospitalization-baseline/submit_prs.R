library(tidyverse)
library(zeallot)
library(covidEnsembles)
library(covidData)
library(here)
setwd(here())

# Location of where component model submissions can be found
setwd("../covid19-forecast-hub/")

forecast_dates <- seq.Date(
  from = as.Date("2020-12-05") + 2 + 7,
  to = as.Date("2021-09-18") + 2,
  by = 7)

for (forecast_date in as.character(forecast_dates)) {
  branch_name <- paste0(
    "hosp_baseline_",
    gsub("-", "", forecast_date)
  )

  system(paste0("git branch ", branch_name))
  system(paste0("git checkout ", branch_name))
  system(paste0("git add data-processed/COVIDhub-baseline/",
    forecast_date,
    "-COVIDhub-baseline.csv"))
  system(paste0("git commit -m 'add hospitalization baseline for ",
    forecast_date,
    ". Forecasts use only data available as of the forecast date.'"))
  system(paste0("git push origin ", branch_name))
  system("git checkout master")
}
