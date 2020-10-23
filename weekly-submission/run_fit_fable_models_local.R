library(tidyr)
library(dplyr)
library(lubridate)

# combinations of methods and dates for which to predict
analysis_combinations <- tidyr::expand_grid(
  forecast_week_end_date = as.character(
    lubridate::ymd('2020-05-30') + seq(from = 0, length = 20)*7),
  model = c('ETS', 'ARIMA'),
  transform_fun = c('box_cox', 'log', 'none'),
  temporal_resolution = 'weekly'
)

for (row_ind in rev(seq_len(nrow(analysis_combinations)))) {
  #foreach(row_ind = seq_len(2)) %dopar% {
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  model <- analysis_combinations$model[row_ind]
  transform_fun <- analysis_combinations$transform_fun[row_ind]
  temporal_resolution <- analysis_combinations$temporal_resolution[row_ind]

  run_cmd <- paste0(
    "R CMD BATCH --vanilla \'--args ",
    forecast_week_end_date, " ",
    model, " ",
    transform_fun, " ",
    temporal_resolution,
    "\' weekly-submission/fit_fable_model_all_locations.R ",
    output_path, "output-", forecast_week_end_date, '-',
    model, '-', transform_fun, '-', temporal_resolution, ".Rout")
  
  system(run_cmd)
}
