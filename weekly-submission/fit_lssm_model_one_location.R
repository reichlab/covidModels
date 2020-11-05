library(doParallel)
library(jsonlite)
library(tidyverse)
library(covidData)
library(lssm)

library(here)
setwd(here())

source("weekly-submission/rstan_functions.r")

args <- commandArgs(trailingOnly = TRUE)
#args <- c('2020-10-10', 'US', 'SARIMA_mle', 'weekly', 'local')
#args <- c('2020-10-10', 'US', 'local_trend', 'daily', 'local')
#args <- c('2020-10-10', 'US', 'SARIMA_mle', 'daily', 'local')
forecast_week_end_date <- lubridate::ymd(args[1])
location <- args[2]
model <- args[3]
temporal_resolution <- args[4]
cluster_local <- args[5]

full_model_case <- paste0(model, "_", temporal_resolution)

if (full_model_case == "SARIMA_mle_weekly") {
  tune_grid <- lssm::sarima_param_grid(
    y = ts(1.0, frequency = 1),
    transformation = c("none", "box-cox", "log"),
    transform_offset = c(0.0, 0.49),
    max_d = 1,
    max_D = 0,
    include_intercept = FALSE,
    max_p_ar = 4,
    max_q_ma = 4,
    max_P_ar = 0,
    max_Q_ma = 0,
    min_order = 1,
    max_order = 5,
    stationary = 1
  ) %>%
    dplyr::filter(
      transformation == "none" & transform_offset == 0.0 |
      transformation == "box-cox" & transform_offset == 0.49 |
      transformation == "log" & transform_offset == 0.49
    )
  ts_frequency <- 1L
  crossval_initial_window <- 4L
} else if (full_model_case == "SARIMA_mle_daily") {
  tune_grid <- lssm::sarima_param_grid(
    y = ts(1.0, frequency = 7),
    transformation = c("none", "box-cox", "log"),
    transform_offset = c(0.0, 0.49),
    max_d = 1,
    max_D = 1,
    include_intercept = FALSE,
    max_p_ar = 4,
    max_q_ma = 4,
    max_P_ar = 2,
    max_Q_ma = 2,
    min_order = 1,
    max_order = 6,
    stationary = 1
  ) %>%
    dplyr::filter(
      transformation == "none" & transform_offset == 0.0 |
      transformation == "box-cox" & transform_offset == 0.49 |
      transformation == "log" & transform_offset == 0.49,
      D + P_ar + Q_ma <= 2,
      d + p_ar + q_ma + D + P_ar + Q_ma <= 5
    )
  ts_frequency <- 7L
  crossval_initial_window <- 28L
}

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

tic <- Sys.time()
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
        temporal_resolution = temporal_resolution,
        measure = measure)
      horizon <- 8L
      types <- c('inc', 'cum')
      required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
    } else if(measure == 'cases') {
      data <- covidData::load_jhu_data(
        issue_date = as.character(forecast_week_end_date + 1),
        spatial_resolution = spatial_resolutions,
        temporal_resolution = temporal_resolution,
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

    if (all(location_data$cum == 0)) {
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
      if (nrow(location_data) < crossval_initial_window + 2 * ts_frequency) {
        crossval_results <- NA

        models_to_use <- tune_grid %>%
          dplyr::filter(
            p_ar + d + q_ma + P_ar + D + Q_ma <= 2
          )
      } else {
        crossval_results <- crossvalidate_lssm(
          y = location_data$inc,
          ts_frequency = ts_frequency,
          initial_window = max(crossval_initial_window, nrow(location_data) - 10 * ts_frequency),
          crossval_start_horizon = 1,
          crossval_end_horizon = min(
            horizon * ts_frequency,
            nrow(location_data) - crossval_initial_window - 1L),
          fixed_window = FALSE,
          crossval_frequency = ts_frequency,
          tune_grid,
          verbose = FALSE,
          parallel = FALSE
        )
        crossval_results$log_score[
          is.infinite(crossval_results$log_score)] <- -Inf

        crossval_summary <- crossval_results %>%
          dplyr::group_by_at(.vars = vars(-fold, -log_score, -run_time)) %>%
          dplyr::summarize(
            mean_log_score = mean(log_score),
            sd_log_score = sd(log_score),
            run_time = sum(run_time)
          ) %>%
          dplyr::arrange(desc(mean_log_score))

        models_to_use <- crossval_summary %>%
          dplyr::ungroup() %>%
          dplyr::filter(
            mean_log_score >= mean_log_score[1] - sd_log_score[1]
          ) %>%
          dplyr::select(-mean_log_score, -sd_log_score, -run_time)
      }

      forecast_inc_trajectories <- purrr::map_dfc(
        seq_len(nrow(models_to_use)),
        function(model_ind) {
          param <- as.list(models_to_use[model_ind, ])
          param$y <- location_data$inc
          param$ts_frequency <- ts_frequency
          param$verbose <- FALSE

          model_fit <- do.call(fit_lssm, param)
              
          result <- predict(
            model_fit,
            newdata = location_data$inc,
            horizon = horizon * ts_frequency,
            forecast_representation = "sample",
            nsim = ceiling(20000 / nrow(models_to_use))
          ) %>%
            as.data.frame()
          colnames(result) <- paste0(colnames(result), '_model', model_ind)

          return(result)
        }
      ) %>% t()

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
    }
  }
  
  write.csv(results, file = forecasts_path, row.names = FALSE)
}
toc <- Sys.time()
toc - tic
