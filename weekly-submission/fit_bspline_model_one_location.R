library(jsonlite)
library(tidyverse)
library(covidData)
library(covidModels)
library(here)
setwd(here())

source("weekly-submission/rstan_functions.r")

args <- commandArgs(trailingOnly = TRUE)
#args <- c('2020-10-10', 'US', 'local_quad', 'weekly', 'local')
forecast_week_end_date <- lubridate::ymd(args[1])
location <- args[2]
model <- args[3]
temporal_resolution <- args[4]
cluster_local <- args[5]

full_model_case <- paste0(model, "_bspline_", temporal_resolution)

# path to cmdstan and where to save model parameter estimates and forecasts
if (cluster_local == "cluster") {
  cmdstan_root <- "~/cmdstan"
  estimates_dir <- paste0('/project/uma_nicholas_reich/covidModels/estimates/',
    full_model_case, '/')
  forecasts_dir <- paste0('/project/uma_nicholas_reich/covidModels/forecasts-by-location/',
    full_model_case, '/')
} else {
  cmdstan_root <- "~/research/tools/cmdstan"
  estimates_dir <- paste0(
    '/home/eray/research/epi/covid/covidModels/weekly-submission/estimates/',
    full_model_case, '/')
  forecasts_dir <- paste0(
    '/home/eray/research/epi/covid/covidModels/weekly-submission/forecasts-by-location/',
    full_model_case, '/')
}

# paths to which 
if(!dir.exists(estimates_dir)) {
  dir.create(estimates_dir)
}
if(!dir.exists(forecasts_dir)) {
  dir.create(forecasts_dir)
}

forecasts_path <- paste0(forecasts_dir,
  forecast_week_end_date + 2,
  '-', full_model_case, '-', location, '.csv')

if(nchar(location) == 5) {
  # county
  measures <- c('cases')
  spatial_resolutions <- 'county'
} else {
  # state or national
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
if (!file.exists(forecasts_path)) {
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
    if (any(location_data$cum > 0)) {
      start_date <- max(
        lubridate::ymd(min(location_data$date)) + 7,
        lubridate::ymd(min(location_data$date[location_data$cum > 0])) - 1 * 7)
      
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
      # parameters specifying model, including knots every 2 weeks
      forecast_horizon <- horizon * ts_frequency
      spline_order <- 3L
      knot_frequency <- 1L * ts_frequency
      all_knots <- seq(
        from = nrow(location_data) %% knot_frequency,
        to = nrow(location_data) + forecast_horizon,
        by = knot_frequency)
      boundary_knots <- all_knots[c(1, length(all_knots))]
      interior_knots <- all_knots[-c(1, length(all_knots))]

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
        "_", full_model_case,
        ".R")
      data_dump_file <- paste0(
        cmdstan_root,
        "/models/", full_model_case, "/", data_dump_file_base)
      # cat(
      #   jsonlite::toJSON(stan_data),
      #   file = data_dump_file
      # )
      stan_rdump(
        names(stan_data),
        file = data_dump_file,
        envir = as.environment(stan_data)
      )

      n_basis <- stan_data$n_interior_knots + 8 - stan_data$spline_order
      stan_init <- list(
#        beta_df = 10.0,
        beta_sd = 1.0,
        raw_beta = rep(0.0, n_basis),
        trend_sd = 1.0,
        raw_trend = rep(0.0, n_basis - 2),
        quad_sd = 1.0,
        raw_quad = rep(0.0, n_basis - 2),
        phi_mean = 1.0,
        phi_sd = 1.0,
        raw_phi = 0.0
      )
      dim(stan_init$raw_beta) <- n_basis
      dim(stan_init$raw_trend) <- n_basis - 2
      dim(stan_init$raw_quad) <- n_basis - 2

      init_dump_file_base <- paste0(
        "init_dump_", forecast_week_end_date,
        "_", location,
        "_", full_model_case,
        ".R")
      init_dump_file <- paste0(
        cmdstan_root,
        "/models/", full_model_case, "/", init_dump_file_base)
      # cat(
      #   jsonlite::toJSON(stan_data),
      #   file = data_dump_file
      # )
      stan_rdump(
        names(stan_init),
        file = init_dump_file,
        envir = as.environment(stan_init)
      )

      # parameter estimation
      setwd(paste0(cmdstan_root, "/models/", full_model_case))
      param_estimates_file <- paste0(
        estimates_dir,
        full_model_case,
        "_", forecast_week_end_date,
        "_location_", location,
        "_measure_", measure, ".csv")
      system(paste0("./", full_model_case, "_model",
        " optimize iter=10000 data file=", data_dump_file_base,
        " init=", init_dump_file_base,
        " output file=", param_estimates_file))
      
      # forecasting
      skiplines <- readLines(param_estimates_file) %>%
        substr(1, 1) %>%
        grepl(pattern = "#", fixed = TRUE) %>%
	      (function(x) { min(which(!x)) - 1 })
      param_estimates <- read_csv(param_estimates_file, skip = skiplines) %>%
        as.data.frame() %>%
        as.vector() %>%
        unlist()
      stan_forecast_data <- stan_data
#      param_names <- c("beta_df", "beta_sd", "raw_beta", "trend_sd",
      param_names <- c("beta_sd", "raw_beta", "trend_sd",
        "raw_trend", "quad_sd", "raw_quad", "phi_mean", "phi_sd", "raw_phi")
      for (param_name in param_names) {
        stan_forecast_data[[param_name]] <- param_estimates[
          grepl(paste0("^", param_name), names(param_estimates))
        ] %>% unname()
        if (param_name %in% c("raw_beta", "raw_trend", "raw_quad")) {
          dim(stan_forecast_data[[param_name]]) <-
            length(stan_forecast_data[[param_name]])
        }
      }
      stan_rdump(
        names(stan_forecast_data),
        file = data_dump_file,
        envir = as.environment(stan_forecast_data)
      )

      predictions_file <- paste0(
        estimates_dir,
        full_model_case,
        "_", forecast_week_end_date,
        "_location_", location,
        "_measure_", measure, "_predictions.csv")
      system(paste0("./", full_model_case, "_predict",
        " optimize iter=1 data file=", data_dump_file_base,
        " init=", init_dump_file_base,
        " output file=", predictions_file))
      
      skiplines <- readLines(predictions_file) %>%
        substr(1, 1) %>%
        grepl(pattern = "#", fixed = TRUE) %>%
        (function(x) { min(which(!x)) - 1 })
      forecast_inc_trajectories <- read_csv(predictions_file, skip = skiplines) %>%
        as.data.frame() %>%
        as.vector() %>%
        unlist()
      forecast_inc_trajectories <- forecast_inc_trajectories[
        grepl("^y_sim", names(forecast_inc_trajectories))
      ]
      dim(forecast_inc_trajectories) <- c(nsim, horizon)

      forecast_inc_trajectories[is.na(forecast_inc_trajectories)] <- 0.0
      forecast_inc_trajectories[forecast_inc_trajectories < 0] <- 0.0

      if (ts_frequency == 7) {
        new_forecast_inc_trajectories <- matrix(
          nrow = nrow(forecast_inc_trajectories),
          ncol = ncol(forecast_inc_trajectories) / 7)
        for (j in seq_len(ncol(new_forecast_inc_trajectories))) {
          new_forecast_inc_trajectories[, j] <- apply(
            forecast_inc_trajectories[, (j - 1) * 7 + seq_len(7)], 1, sum)
        }

        forecast_inc_trajectories <- new_forecast_inc_trajectories
      }

      quantile_forecast <- NULL
      if ("inc" %in% types) {
        quantile_forecast <- dplyr::bind_rows(
          quantile_forecast,
          purrr::map_dfr(
            seq_len(horizon),
            function(h) {
              data.frame(
                horizon = h,
                type = 'inc',
                quantile = required_quantiles,
                value = quantile(
                  forecast_inc_trajectories[, h],
                  probs = required_quantiles,
                  na.rm = TRUE),
                stringsAsFactors = FALSE
              )
            }
          )
        )
      }
      
      if ("cum" %in% types) {
        # initialize sampled cumulative incidence at the most recent observed value
        sampled_cum <- tail(location_data$cum, 1)
        
        for (h in seq_len(horizon)) {
          # update sampled cumulative incidence
          sampled_cum <- sampled_cum + forecast_inc_trajectories[, h]
          
          quantile_forecast <- bind_rows(
            quantile_forecast,
            data.frame(
              horizon = h,
              type = 'cum',
              quantile = required_quantiles,
              value = quantile(sampled_cum, probs = required_quantiles),
              stringsAsFactors = FALSE
            )
          )
        }
      }

      quantile_forecast <- quantile_forecast %>%
        dplyr::transmute(
          forecast_date = as.character(forecast_week_end_date + 2),
          target = paste0(horizon, ' wk ahead ', type, ' ', substr(measure, 1, nchar(measure)-1)),
          target_end_date = as.character(forecast_week_end_date  + 7*horizon),
          location = location,
          type = 'quantile',
          quantile = quantile,
          value = round(value)
        )
      
      location_results <- dplyr::bind_rows(
        quantile_forecast,
        quantile_forecast %>%
          dplyr::filter(quantile == 0.5) %>%
          dplyr::mutate(
            type = 'point',
            quantile = NA_real_
          )
      )

      measure_results <- location_results
    
      results <- dplyr::bind_rows(
        results,
        measure_results
      )
      
      # clean up
      unlink(data_dump_file)
      unlink(init_dump_file)
      unlink(param_estimates_file)
      unlink(predictions_file)
    }
  }
  
  write.csv(results, file = forecasts_path, row.names = FALSE)
}
