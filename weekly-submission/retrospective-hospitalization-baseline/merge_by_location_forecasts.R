library(tidyr)
library(dplyr)
library(readr)
library(lubridate)

required_locations <- readr::read_csv('https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv') %>%
  dplyr::filter(nchar(location) == 2) %>%
  dplyr::pull(location)

# forecast_week_end_dates <- seq.Date(
#   from = as.Date("2020-12-05"),
#   to = lubridate::floor_date(Sys.Date(), unit = "week", week_start = 6),
#   by = 7)
forecast_week_end_dates <- seq.Date(
  from = as.Date("2020-12-05"),
  to = as.Date("2021-09-18"),
  by = 7)

path_by_location <- "weekly-submission/retrospective-hospitalization-baseline/forecasts-by-location/"
path_merged <- "weekly-submission/retrospective-hospitalization-baseline/forecasts/"

# combinations of methods and dates for which to predict
models <- list.dirs(path_by_location, full.names=FALSE, recursive=FALSE)

analysis_combinations <- tidyr::expand_grid(
  forecast_week_end_date = forecast_week_end_dates,
  model = models
)

for (row_ind in seq_len(nrow(analysis_combinations))) {
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  model <- analysis_combinations$model[row_ind]

  model_paths_by_location <- paste0(
    path_by_location,
    model, "/",
    lubridate::ymd(forecast_week_end_date) + 2,
    "-", model,
    "-", required_locations,
    ".csv"
  )
  model_dir_merged <- paste0(path_merged, model, "/")
  model_path_merged <- paste0(
    model_dir_merged,
    lubridate::ymd(forecast_week_end_date) + 2,
    "-", model, ".csv"
  )
  if (!dir.exists(model_dir_merged)) {
    dir.create(model_dir_merged, recursive = TRUE)
  }

  if (file.exists(model_path_merged)) {
    print(paste0("Already done; skipping ", model_path_merged))
#  } else if (!all(file.exists(model_paths_by_location))) {
#    print(paste0("Missing location files; skipping ", model_path_merged))
  } else {
    print(paste0("Merging ", model_path_merged))
    model_paths_by_location <- model_paths_by_location[file.exists(model_paths_by_location)]

    merged_results <- purrr::map_dfr(
      model_paths_by_location,
      function(path) {
        read_csv(
          path,
          col_types = cols(
            forecast_date = col_character(),
            target = col_character(),
            target_end_date = col_character(),
            location = col_character(),
            type = col_character(),
            quantile = col_character(),
            value = col_character()
          ))
      }
    )

    write_csv(merged_results, model_path_merged)
  }
}
