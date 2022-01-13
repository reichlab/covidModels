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


for (forecast_week_end_date in forecast_week_end_dates) {
  forecast_week_end_date <- lubridate::ymd(forecast_week_end_date)
  
  results_path <- paste0('weekly-submission/forecasts/COVIDhub-baseline/',
                         forecast_week_end_date + 2,
                         '-COVIDhub-baseline.csv')
  if (TRUE) {
#  if(!file.exists(results_path)) {
    results <- NULL
    for (measure in c('deaths', 'cases', 'hospitalizations')) {
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
          measure = measure,
          source = "covidcast") %>%
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
    target_variables = c("cases", "deaths", "hospitalizations")
  )
}



# for(forecast_week_end_date in forecast_week_end_dates) {
#   forecast_week_end_date <- lubridate::ymd(forecast_week_end_date)
  
#   results_path <- paste0('weekly-submission/forecasts/COVIDhub-baseline/',
#                          forecast_week_end_date + 2,
#                          '-COVIDhub-baseline.csv')
#   if(!file.exists(results_path)) {
#     stop(paste0('missing file: ', results_path))
#   }
  
#   results <- read.csv(results_path, stringsAsFactors = FALSE)
#   for(measure in c('deaths', 'cases')) {
#     if(measure == 'deaths') {
#       data <- covidData::load_jhu_data(
#         issue_date = as.character(forecast_week_end_date + 1),
#         spatial_resolution = c('state', 'national'),
#         temporal_resolution = 'weekly',
#         measure = measure)
#       horizon <- 8L
#       types <- c('inc', 'cum')
#       required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
#     } else if(measure == 'cases') {
#       data <- covidData::load_jhu_data(
#         issue_date = as.character(forecast_week_end_date + 1),
#         spatial_resolution = c('county', 'state', 'national'),
#         temporal_resolution = 'weekly',
#         measure = measure)
#       horizon <- 8L
#       types <- 'inc'
#       required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
#     }
    
#     location_batches <- results %>%
#       dplyr::filter(grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
#       dplyr::distinct(location) %>%
#       dplyr::arrange(nchar(location), location) %>%
#       dplyr::mutate(
#         location = factor(location, levels = location),
#         batch = rep(seq_len(ceiling(nrow(.)/30)), each = 30)[seq_len(nrow(.))]
#       )
    
#     pdf(paste0('weekly-submission/COVIDhub-baseline-plots/',
#                forecast_week_end_date + 2,
#                '-COVIDhub-baseline-plots-', measure, '.pdf'),
#       width=24, height=14)
    
#     for(batch_val in unique(location_batches$batch)) {
#       print(batch_val)
#       batch_locations <- location_batches$location[location_batches$batch == batch_val]
#       plottable_predictions <- results %>%
#         dplyr::filter(
#           location %in% batch_locations,
#           grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
#         dplyr::mutate(
#           endpoint_type = ifelse(quantile < 0.5, 'lower', 'upper'),
#           alpha = ifelse(
#             endpoint_type == 'lower',
#             format(2*quantile, digits=3, nsmall=3),
#             format(2*(1-quantile), digits=3, nsmall=3))
#         ) %>%
#         dplyr::select(-quantile) %>%
#         tidyr::pivot_wider(names_from='endpoint_type', values_from='value')
    
#     #  batch_locations <- c('05', '10')
    
#       for(type in types) {
#         p <- ggplot() +
#           geom_line(data=data %>% 
#                       dplyr::mutate(date = lubridate::ymd(date)) %>%
#                       dplyr::filter(location %in% batch_locations),
#                     mapping = aes_string(x = "date", y = type, group = "location")) +
#           geom_point(data=data %>% 
#                        dplyr::mutate(date = lubridate::ymd(date)) %>%
#                        dplyr::filter(location %in% batch_locations),
#                     mapping = aes_string(x = "date", y = type, group = "location")) +
#           geom_ribbon(
#             data = plottable_predictions %>% dplyr::filter(location %in% batch_locations) %>%
#               filter(alpha != "1.000", grepl(UQ(type), target)) %>%
#               mutate(
#                 horizon = as.integer(substr(target, 1, 1)),
#                 target_end_date = forecast_week_end_date + 7*horizon),
#             mapping = aes(x = target_end_date,
#                           ymin=lower, ymax=upper,
#                           fill=alpha)) +
#           geom_line(
#             data = results %>% dplyr::filter(location %in% batch_locations) %>%
#               filter(quantile == 0.5,
#                      grepl(UQ(type), target),
#                      grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
#               mutate(
#                 horizon = as.integer(substr(target, 1, 1)),
#                 target_end_date = forecast_week_end_date + 7*horizon),
#             mapping = aes(x = target_end_date, y = value)) +
#           geom_point(
#             data = results %>% dplyr::filter(location %in% batch_locations) %>%
#               filter(quantile == 0.5,
#                      grepl(UQ(type), target),
#                      grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
#               mutate(
#                 horizon = as.integer(substr(target, 1, 1)),
#                 target_end_date = forecast_week_end_date + 7*horizon),
#             mapping = aes(x = target_end_date, y = value)) +
#           facet_wrap(~location, ncol=6, scales = 'free_y') +
#           ggtitle(paste(type, measure, as.character(forecast_week_end_date))) +
#           theme_bw()
#         print(p)
#       }
#     }
#     dev.off()
#   }
# }
