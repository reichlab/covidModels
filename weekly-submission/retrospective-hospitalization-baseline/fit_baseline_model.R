library(tidyverse)
library(covidData)
library(covidModels)
library(here)
setwd(here())

# start date for data -- after most data irregularities
start_date <- as.Date("2020-10-01")

args <- commandArgs(trailingOnly = TRUE)
#args <- c("01", "2021-05-03")

location <- args[1]
forecast_week_end_date <- lubridate::ymd(args[2])

target_variable <- "hospitalizations"
temporal_resolution <- "daily"
model <- "quantile_baseline"

results_dir <- file.path("weekly-submission/retrospective-hospitalization-baseline/forecasts-by-location", model)
if (!dir.exists(results_dir)) {
  dir.create(results_dir, recursive = TRUE)
}

results_filename <- paste0(
  forecast_week_end_date + 2, "-",
  model, "-",
  location, ".csv")
results_path <- file.path(results_dir, results_filename)

if (!file.exists(results_path)) {
  if (location == "US") {
    spatial_resolution <- "national"
  } else if (nchar(location) == 2) {
    spatial_resolution <- "state"
  } else if (nchar(location) == 5) {
    spatial_resolution <- "county"
  } else {
    stop("Invalid location")
  }

  if (target_variable == "deaths") {
    horizon <- 8L
    types <- c("inc", "cum")
    required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
    output_target <- "death"
  } else if (target_variable == "cases") {
    horizon <- 8L
    types <- "inc"
    required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
    output_target <- "case"
  } else if (target_variable == "hospitalizations") {
    horizon <- 28L
    types <- "inc"
    required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
    output_target <- "hosp"
  } else {
    stop("Invalid target_variable")
  }

  # use data available as of the monday of submission
  # (by convention established for weekly targets,
  # forecast_week_end_date is a Saturday)
  as_of <- as.character(forecast_week_end_date + 2)

  location_data <- covidData::load_data(
    as_of = as_of,
    location_code = location,
    spatial_resolution = spatial_resolution,
    temporal_resolution = temporal_resolution,
    measure = target_variable,
    source = "covidcast") %>%
    dplyr::filter(date >= start_date) %>%
    dplyr::arrange(date)

  # drop leading zeros and NAs
  first_non_na_ind <- min(which(!is.na(location_data$inc)))
  location_data <- location_data[first_non_na_ind:nrow(location_data), ]

  if (location_data$inc[1] == 0) {
    non_zero_inds <- which(location_data$inc != 0)
    if (length(non_zero_inds) > 0) {
      first_non_zero_ind <- min(non_zero_inds)
      location_data <- location_data[first_non_zero_ind:nrow(location_data), ]
    }
  }

  # set cumulative values to 0 if we're modeling hospitalizations
  if (target_variable == "hospitalizations") {
    location_data$cum <- 0
  }

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

  if (model == "quantile_baseline") {
    baseline_fit <- covidModels::fit_quantile_baseline(location_data$inc)
  } else {
    stop("Invalid model")
  }

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
      type = "quantile",
      quantile = quantile,
      value = value
    )

  full_forecast <- dplyr::bind_rows(
    quantile_forecast,
    quantile_forecast %>%
      dplyr::filter(quantile == 0.5) %>%
      dplyr::mutate(
        type = "point",
        quantile = NA_real_
      )
  )

  write.csv(full_forecast, file = results_path, row.names = FALSE)
}
