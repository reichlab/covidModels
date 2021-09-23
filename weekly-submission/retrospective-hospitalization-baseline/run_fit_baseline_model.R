library(tidyr)
library(dplyr)
library(lubridate)
library(doParallel)

registerDoParallel(cores = 28)

output_path <- 'weekly-submission/retrospective-hospitalization-baseline/log/'
if (!dir.exists(output_path)) {
  dir.create(output_path, recursive = TRUE)
}

required_locations <- readr::read_csv('https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv') %>%
  dplyr::filter(
    # state and national level only
    nchar(location) == 2,
    # drop locations without hospitalizations data
    !(location %in% c("60", "66", "69", "74"))
  )

# forecast_week_end_dates <- seq.Date(
#   from = as.Date("2020-12-05"),
#   to = lubridate::floor_date(Sys.Date(), unit = "week", week_start = 6),
#   by = 7)
forecast_week_end_dates <- seq.Date(
  from = as.Date("2020-12-05"),
  to = as.Date("2021-09-18"),
  by = 7)

# combinations of locations and dates for which to build baseline model
analysis_combinations <- tidyr::expand_grid(
  location = required_locations$location,
  forecast_week_end_date = forecast_week_end_dates
)

foreach(row_ind = seq_len(nrow(analysis_combinations))) %dopar% {
#foreach(row_ind = seq_len(16)) %dopar% {
  #foreach(row_ind = seq_len(2)) %dopar% {
  location <- analysis_combinations$location[row_ind]
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]

  run_cmd <- paste0(
    "R CMD BATCH --vanilla \'--args ",
    location, " ",
    forecast_week_end_date,
    "\' weekly-submission/retrospective-hospitalization-baseline/fit_baseline_model.R ",
    output_path, "output-", location, '-', forecast_week_end_date, ".Rout")

  system(run_cmd)
}

# get locations for failed jobs -- expect none
analysis_combinations %>%
  dplyr::mutate(
    forecast_file = paste0("weekly-submission/retrospective-hospitalization-baseline/forecasts-by-location/quantile_baseline/",
      forecast_week_end_date + 2, "-quantile_baseline-", location, ".csv"),
    run_succeeded = file.exists(forecast_file)
  ) %>%
  dplyr::filter(!run_succeeded) %>%
  dplyr::distinct(location)

