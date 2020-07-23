library(tidyr)
library(dplyr)
library(lubridate)
library(doParallel)

registerDoParallel(cores = 6)

output_path <- 'weekly-submission/log/'


# basic approaches
analysis_combinations <- tidyr::expand_grid(
  forecast_week_end_date = as.character(
    lubridate::ymd('2020-05-09') + seq(from = 0, length = 10)*7),
  model = c('quantile_baseline-symmetrize_TRUE', 'quantile_baseline-symmetrize_FALSE'),
  temporal_resolution = 'weekly',
  window_size = '8',
  transformation = c('none', 'log'),
  d = c(0, 1)
)

foreach(row_ind = seq_len(nrow(analysis_combinations))) %dopar% {
  #foreach(row_ind = seq_len(2)) %dopar% {
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  model <- analysis_combinations$model[row_ind]
  temporal_resolution <- analysis_combinations$temporal_resolution[row_ind]
  window_size <- analysis_combinations$window_size[row_ind]
  transformation <- analysis_combinations$transformation[row_ind]
  d <- analysis_combinations$d[row_ind]

  run_cmd <- paste0(
    "R CMD BATCH --vanilla \'--args ",
    forecast_week_end_date, " ",
    model, " ",
    temporal_resolution, " ",
    window_size, " ",
    transformation, " ",
    d,
    "\' weekly-submission/fit_simple_ts_model.R ",
    output_path, "output-", forecast_week_end_date, '-',
    model, '-', temporal_resolution, '-',
    window_size, '-', transformation, '-', d, ".Rout")
  
  system(run_cmd)
}
