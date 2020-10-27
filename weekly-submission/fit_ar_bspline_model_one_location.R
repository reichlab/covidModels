library(jsonlite)
library(tidyverse)
library(covidData)
library(covidModels)
library(here)
setwd(here())

source("rstan_functions.r")

args <- commandArgs(trailingOnly = TRUE)
#args <- c('2020-05-30', 'ETS', 'box_cox', 'weekly')
#args <- c('2020-10-10', '56045', 'ETS', 'none', 'weekly')
forecast_week_end_date <- lubridate::ymd(args[1])
location <- args[2]
temporal_resolution <- args[3]

# path to cmdstan
cmdstan_root <- "~/cmdstan" # cluster
#cmdstan_root <- "~/research/tools/cmdstan" # evan's computer

# paths to which to save model parameter estimates and forecasts
full_model_case <- paste0("ar_bspline_", temporal_resolution)
estimates_dir <- paste0('/project/uma_nicholas_reich/covidModels/estimates/', full_model_case, '/')
forecasts_dir <- paste0('/project/uma_nicholas_reich/covidModels/forecasts/', full_model_case, '/')
if(!dir.exists(estimates_dir)) {
  dir.create(estimates_dir)
}
if(!dir.exists(forecasts_dir)) {
  dir.create(forecasts_dir)
}

results_path <- paste0(model_dir,
  forecast_week_end_date + 2,
  '-', full_model_case, '-', location, '.csv')

if(nchar(location) == 5) {
  measures <- c('cases')
  spatial_resolutions <- 'county'
} else {
  measures <- c('deaths', 'cases')
  spatial_resolutions <- c('state', 'national')
}

# time series frequency; number of observations in one week
if (temporal_resolution == "weekly") {
  ts_frequency <- 1L
} else {
  ts_frequency <- 7L
}

# number of simulations for sampling from predictive distributions
nsim <- 5000L

# Get the model fits and predictions
if(!file.exists(results_path)) {
  results <- NULL

  # Separate fits for each measure
  for(measure in measures) {
    print(measure)
    if(measure == 'deaths') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = spatial_resolutions,
        temporal_resolution = 'weekly',
        measure = measure)
      horizon <- 8L
      types <- c('inc', 'cum')
      required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
    } else if(measure == 'cases') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = spatial_resolutions,
        temporal_resolution = 'weekly',
        measure = measure)
      horizon <- 8L
      types <- 'inc'
      required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
    }
    
    # Subset to specified location
    location_data <- data %>%
      dplyr::filter(location == UQ(location))
    
    # correct negative incidence -- to do later via covidData
    location_data$inc[location_data$inc < 0] <- 0.0

    # subset to start one time point before the first case
    if (any(location_data$cum) > 0) {
      start_date <- max(
        lubridate::ymd(min(location_data$date)) + 7,
        lubridate::ymd(min(location_data$date[location_data$cum > 0])) - 1*7)
      
      location_data <- location_data %>%
        dplyr::filter(date >= as.character(start_date)) %>%
        dplyr::mutate(offset_inc = inc + 0.49)
    }

    if (all(location_data$cum == 0) ||
        nrow(location_data) < 3 * ts_frequency) {
      # not enough observations to fit the spline model, so instead fit a
      # heuristic model describing distribution of first non-zero incidence
      first_inc <- data %>%
  	    dplyr::group_by(location) %>%
        dplyr::filter(cum > 0) %>%
        dplyr::filter(cum == min(cum)) %>%
        dplyr::pull(inc)
      first_inc <- c(first_inc, rep(0, 3 * length(first_inc)))
      null_baseline <- covidModels::new_quantile_baseline(
        inc_diffs = first_inc,
        symmetrize = FALSE)
      
      forecast_inc_trajectories <- predict(
        null_baseline,
        inc_data = 0,
        quantiles = seq(from = 0.001, to = 0.999, by = 0.001),
        horizon = horizon,
        num_samples = nsim) %>%
        dplyr::filter(type == "inc") %>%
        tidyr::pivot_wider(names_from = "horizon", values_from = "value") %>%
        dplyr::select(-type, -quantile) %>%
        as.matrix()
    } else {
      # set up knots every 2 weeks
      knot_frequency <- 2L * ts_frequency
      all_knots <- seq(
        from = nrow(data) %% knot_frequency,
        to = nrow(data) + forecast_horizon,
        by = knot_frequency)
      boundary_knots <- all_knots[c(1, length(all_knots))]
      interior_knots <- all_knots[-c(1, length(all_knots))]

      # other parameters specifying model
      forecast_horizon <- horizon * ts_frequency
      spline_order <- 3L

      # create data for stan model and output to file
      stan_data <- list(
        T = nrow(location_data),
        y = as.integer(location_data$inc),
        spline_order = spline_order,
        n_interior_knots = length(interior_knots),
        interior_knots = interior_knots,
        boundary_knots = boundary_knots,
        forecast_horizon = forecast_horizon,
        nsim = nsim
      )
      data_dump_file_base <- paste0(
        "data_dump_", forecast_week_end_date,
        "_", location,
        "_", temporal_resolution,
        ".json")
      data_dump_file <- paste0(
        cmdstan_root,
        "/models/ar_bspline_model_", temporal_resolution,
        "/", data_dump_file_base)
      # cat(
      #   jsonlite::toJSON(stan_data),
      #   file = data_dump_file
      # )
      stan_rdump(
        names(stan_data),
        file = data_dump_file,
        envir = as.environment(stan_data)
      )

      # parameter estimation
      setwd(paste0(cmdstan_root, "/models/ar_bspline_model_", temporal_resolution))
      param_estimates_file <- paste0(
        output_path,
        "ar_bspline_param_estimates_", forecast_week_end_date,
        "_location_", location,
        "_measure_", measure, ".csv")
      system(paste0("./ar_bspline_model_", temporal_resolution,
        " optimize data file=", data_dump_file_base,
        #" init=", init_dump_file_base,
        " output file=", output_file))
    }
  }
}
