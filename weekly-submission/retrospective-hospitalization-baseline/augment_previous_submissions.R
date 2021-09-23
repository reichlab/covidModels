library(tidyr)
library(dplyr)
library(readr)
library(lubridate)

orig_forecasts_base_path <- "../covid19-forecast-hub/data-processed/COVIDhub-baseline"
hosp_forecasts_base_path <- "weekly-submission/retrospective-hospitalization-baseline/forecasts/quantile_baseline"

forecast_week_end_dates <- seq.Date(
  from = as.Date("2020-12-05"),
  to = as.Date("2021-09-18"),
  by = 7)

# combinations of methods and dates for which to predict
models <- "quantile_baseline"

analysis_combinations <- tidyr::expand_grid(
  forecast_week_end_date = forecast_week_end_dates,
  model = models
)

for (row_ind in seq_len(nrow(analysis_combinations))) {
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  model <- analysis_combinations$model[row_ind]

  hosp_forecasts_path <- paste0(
    hosp_forecasts_base_path, "/",
    lubridate::ymd(forecast_week_end_date) + 2,
    "-", model, ".csv"
  )

  hosp_forecasts <- readr::read_csv(
    file = hosp_forecasts_path,
    col_types = cols(
      forecast_date = col_character(),
      target = col_character(),
      target_end_date = col_character(),
      location = col_character(),
      type = col_character(),
      quantile = col_double(),
      value = col_double()
    )
  )

  orig_forecasts_path <- paste0(
    orig_forecasts_base_path, "/",
    lubridate::ymd(forecast_week_end_date) + 2,
    "-COVIDhub-baseline.csv"
  )

  orig_forecasts <- readr::read_csv(
    file = orig_forecasts_path,
    col_types = cols(
      forecast_date = col_character(),
      target = col_character(),
      target_end_date = col_character(),
      location = col_character(),
      type = col_character(),
      quantile = col_double(),
      value = col_double()
    )
  )

  merged_forecasts <- dplyr::bind_rows(orig_forecasts, hosp_forecasts)

  # use write.csv to match previous formatting
  write.csv(merged_forecasts, file = orig_forecasts_path, row.names = FALSE)
}
