library(tidyr)
library(dplyr)
library(readr)
library(lubridate)

by_location_path <- "weekly-submission/forecasts-by-location/"

required_locations <- readr::read_csv(
  'https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv'
)$location

# combinations of methods and dates for which to predict
analysis_combinations <- tidyr::expand_grid(
  forecast_week_end_date = as.character(
    lubridate::ymd('2020-05-30') + seq(from = 0, length = 23)*7),
  model = c("SARIMA_mle"), #, "damped_local_quad_bspline"),
  temporal_resolution = c("weekly", "daily")
)

path_by_location <- "weekly-submission/forecasts-by-location/"
path_merged <- "weekly-submission/forecasts/"

for (row_ind in seq_len(nrow(analysis_combinations))) {
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  model <- analysis_combinations$model[row_ind]
  temporal_resolution <- analysis_combinations$temporal_resolution[row_ind]

  model_paths_by_location <- paste0(
    path_by_location,
    model, "_", temporal_resolution, "/",
    lubridate::ymd(forecast_week_end_date) + 2,
    "-", model, "_", temporal_resolution,
    "-", required_locations,
    ".csv"
  )
  model_dir_merged <- paste0(
    path_merged,
    model, "_", temporal_resolution, "/"
  )
  model_path_merged <- paste0(
    model_dir_merged,
    lubridate::ymd(forecast_week_end_date) + 2,
    "-", model, "_", temporal_resolution, ".csv"
  )
  if (!dir.exists(model_dir_merged)) {
    dir.create(model_dir_merged)
  }

  if (file.exists(model_path_merged)) {
    print(paste0("Already done; skipping ", model_path_merged))
  } else if (!all(file.exists(model_paths_by_location))) {
    print(paste0("Missing location files; skipping ", model_path_merged))
  } else {
    print(paste0("Merging ", model_path_merged))

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
