library(tidyverse)
library(covidData)
library(covidModels)
library(here)
setwd(here())

required_locations <- readr::read_csv('https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv')

# Figure out what day it is; forecast creation date is set to a Monday,
# even if we are delayed and create it Tuesday morning.
forecast_week_end_dates <- as.character(
  lubridate::floor_date(Sys.Date(), unit = "week") - 1
)

if (!dir.exists('weekly-submission/COVIDhub-baseline-plots/')) {
  dir.create('weekly-submission/COVIDhub-baseline-plots/', recursive = TRUE)
}

for (forecast_week_end_date in forecast_week_end_dates) {
  forecast_week_end_date <- lubridate::ymd(forecast_week_end_date)
  
  results_dir <- 'weekly-submission/forecasts/COVIDhub-baseline/'
  if (!dir.exists(results_dir)) {
    dir.create(results_dir, recursive = TRUE)
  }
  results_path <- paste0(results_dir,
                         forecast_week_end_date + 2,
                         '-COVIDhub-baseline.csv')
  if (TRUE) {
#  if(!file.exists(results_path)) {
    results <- NULL
    for (measure in c('hospitalizations')) {
      if (measure == 'deaths') {
        data <- covidData::load_jhu_data(
          issue_date = as.character(forecast_week_end_date + 1),
          spatial_resolution = c('state', 'national'),
          temporal_resolution = 'weekly',
          measure = measure) %>%
          dplyr::filter(location %in% required_locations$location)
        horizon <- 8L
        temporal_resolution <- "weekly"
        types <- c('inc', 'cum')
        required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
        output_target <- "death"
      } else if (measure == 'cases') {
        data <- covidData::load_jhu_data(
          issue_date = as.character(forecast_week_end_date + 1),
          spatial_resolution = c('county', 'state', 'national'),
          temporal_resolution = 'weekly',
          measure = measure) %>%
          dplyr::filter(location %in% required_locations$location)
        horizon <- 8L
        temporal_resolution <- "weekly"
        types <- 'inc'
        required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
        output_target <- "case"
      } else if (measure == 'hospitalizations') {
        data <- covidData::load_data(
          # note: it is appropriate to use as_of = the forecast date when
          # pulling data from covidcast
          as_of = as.character(forecast_week_end_date + 2),
          spatial_resolution = c('state', 'national'),
          temporal_resolution = 'daily',
          measure = measure) %>%
          dplyr::filter(location %in% required_locations$location) %>%
          dplyr::arrange(location, date)
        horizon <- 28L
        temporal_resolution <- "daily"
        types <- 'inc'
        required_quantiles <-c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
        output_target <- "hosp"
      }
      
      measure_results <- purrr::map_dfr(
        unique(data$location),
        function(location) {
          location_data <- data %>%
            dplyr::filter(location == UQ(location))

          # drop leading zeros and NAs
          first_non_na_ind <- min(which(!is.na(location_data$inc)))
          location_data <- location_data[first_non_na_ind:nrow(location_data), ]

          if (location_data$inc[1] == 0) {
            non_zero_inds <- which(location_data$inc != 0)
            if (length(non_zero_inds) > 0) {
              first_non_zero_ind <- min(non_zero_inds)
              if (first_non_zero_ind == nrow(location_data)) {
                first_non_zero_ind <- first_non_zero_ind - 1
              }
              location_data <- location_data[first_non_zero_ind:nrow(location_data), ]
            }
          }

          # set cumulative values to 0 if we're modeling hospitalizations
          # subset data, dropping values before we have reliable data
          if (measure == "hospitalizations") {
            location_data$cum <- 0
            start_date <- "2020-10-01"
          } else {
            # keep everything
            start_date <- lubridate::ymd(min(location_data$date))
          }
          
          location_data <- location_data %>%
            dplyr::filter(date >= as.character(start_date))

          if (temporal_resolution == "weekly") {
            output_time_unit <- "wk"
            days_per_time_unit <- 7L
            effective_horizon <- horizon
            horizon_adjustment <- 0L
          } else if (temporal_resolution == "daily") {
            output_time_unit <- "day"
            days_per_time_unit <- 1L

            # figure out what horizon we need to forecast for, accounting for
            # differences between the last available data date and the Monday relative
            # to which forecast targets/horizons are defined
            last_data_date <- max(location_data$date)
            last_target_date <- forecast_week_end_date + 2 + horizon
            effective_horizon <- last_target_date - last_data_date
            horizon_adjustment <- as.integer(effective_horizon - horizon)
          }

          baseline_fit <- covidModels::fit_quantile_baseline(location_data$inc)
    
          quantile_forecast <- predict(
            baseline_fit,
            inc_data = location_data$inc,
            cum_data = location_data$cum,
            quantiles = required_quantiles,
            horizon = effective_horizon,
            num_samples = 100000
          ) %>%
            dplyr::mutate(horizon = horizon - horizon_adjustment) %>%
            dplyr::filter(horizon > 0, type %in% types) %>%
            dplyr::transmute(
              forecast_date = as.character(forecast_week_end_date + 2),
              target = paste0(horizon, " ", output_time_unit, " ahead ", type, " ", output_target),
              target_end_date = as.character(
                forecast_week_end_date +
                  2 * as.integer(temporal_resolution == "daily") +
                  days_per_time_unit * horizon),
              location = location,
              type = 'quantile',
              quantile = quantile,
              value = value
            )
          
          return(
            dplyr::bind_rows(
              quantile_forecast,
              quantile_forecast %>%
                dplyr::filter(quantile == 0.5) %>%
                mutate(
                  type = 'point',
                  quantile = NA_real_
                )
            )
          )
        })
      
      results <- dplyr::bind_rows(
        results,
        measure_results
      )
    }
    
    write.csv(results, file = results_path, row.names = FALSE)
  }

  # plot forecasts
  covidModels::plot_forecasts_single_model(
    submissions_root = 'weekly-submission/forecasts/',
    plots_root = 'weekly-submission/COVIDhub-baseline-plots/',
    forecast_date = forecast_week_end_date + 2,
    model_abbrs = "COVIDhub-baseline",
    target_variables = c("hospitalizations")
  )
}
