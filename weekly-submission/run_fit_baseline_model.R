library(tidyr)
library(dplyr)
library(lubridate)
library(doParallel)

registerDoParallel(cores = 6)

output_path <- 'weekly-submission/log/'

required_locations <- readr::read_csv('https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv')

# basic approaches
analysis_combinations <- tidyr::expand_grid(
  location = required_locations$location,
  forecast_week_end_date = '2020-07-25',
  model = 'quantile_baseline-symmetrize_TRUE',
  temporal_resolution = 'weekly',
  window_size = 'NA',
  transformation = 'none',
  d = 0
)

foreach(row_ind = seq_len(nrow(analysis_combinations))) %dopar% {
  #foreach(row_ind = seq_len(2)) %dopar% {
  location <- analysis_combinations$location[row_ind]
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  model <- analysis_combinations$model[row_ind]
  temporal_resolution <- analysis_combinations$temporal_resolution[row_ind]
  window_size <- analysis_combinations$window_size[row_ind]
  transformation <- analysis_combinations$transformation[row_ind]
  d <- analysis_combinations$d[row_ind]

  run_cmd <- paste0(
    "R CMD BATCH --vanilla \'--args ",
    location, " ",
    forecast_week_end_date, " ",
    model, " ",
    temporal_resolution, " ",
    window_size, " ",
    transformation, " ",
    d,
    "\' weekly-submission/fit_simple_ts_model.R ",
    output_path, "output-", location, '-', forecast_week_end_date, '-',
    model, '-', temporal_resolution, '-',
    window_size, '-', transformation, '-', d, ".Rout")
  
  system(run_cmd)
}
