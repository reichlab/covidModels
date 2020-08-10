library(zoltr)
library(tidyverse)
library(zeallot)
library(covidData)
library(googledrive)

submissions_root <- '~/Documents/research/epi/covid/covidModels/weekly-submission/'

plots_root <- '~/Documents/research/epi/covid/covidModels/weekly-submission/plots/'

# Figure out what day it is.
# forecast_week_end_date is a saturday relative to which week-ahead targets are
# defined. forecast_date is the monday of forecast submission
#current_wday <- lubridate::wday(Sys.Date(), label = TRUE)
#forecast_week_end_date <- if(current_wday == 'Mon') {
#  Sys.Date() - 2
#} else if(current_wday == 'Tue') {
#  Sys.Date() - 3
#} else {
#  stop('unsupported current_wday')
#}

forecast_week_end_date <- lubridate::ymd('2020-05-09')

forecast_date <- forecast_week_end_date + 2

day_plots_root <- paste0(plots_root, forecast_date, '/')
if(!file.exists(day_plots_root)) {
  dir.create(day_plots_root)
}

submission_dates <- forecast_date + seq(from = -6, to = 0)

# List of candidate models for inclusion in ensemble
candidate_model_abbreviations_to_include <- 'spline_smoother-temporal_resolution_weekly-window_size_NA-transformation_none-d_0'

fips_codes <- covidData::fips_codes %>%
  dplyr::mutate(
    state_code = ifelse(
      nchar(location > 2),
      substr(location, 1, 2),
      location
    )
  ) %>%
  dplyr::left_join(
    covidData::fips_codes %>%
      dplyr::filter(nchar(location) == 2) %>%
      dplyr::select(state_code = location, state_abbr = abbreviation),
    by = 'state_code'
  ) %>%
  dplyr::mutate(
    location_name = ifelse(
      nchar(location) > 2,
      paste0(location_name, ', ', state_abbr),
      location_name
    )
  ) %>%
  dplyr::select(location, location_name)


for(model_abbr in candidate_model_abbreviations_to_include) {
  results_path <- paste0(submissions_root, model_abbr, '/',
    submission_dates, '-', model_abbr, '.csv')
  results_path <- results_path[file.exists(results_path)]
  results_path <- tail(results_path, 1)

  if(length(results_path) == 0) {
    # no forecasts for this week
    next
  }

  model_forecast_date <- strsplit(results_path, split = '/')[[1]] %>%
    tail(1) %>%
    substr(1, 10)

  results <- readr::read_csv(
    results_path,
    col_types = cols(
      forecast_date = col_date(format = ""),
      target = col_character(),
      target_end_date = col_date(format = ""),
      location = col_character(),
      type = col_character(),
      quantile = col_double(),
      value = col_double()
    )) %>%
    dplyr::left_join(fips_codes, by = 'location')

  one_week_target_date <- results %>%
    dplyr::filter(grepl('^1 wk', target)) %>%
    dplyr::pull(target_end_date) %>%
    tail(1)
  if(!(one_week_target_date == (forecast_week_end_date + 7))) {
    # forecast file targets wrong week
    next
  }

  for(measure in c('deaths', 'cases')) {
    plot_path <- paste0(day_plots_root, model_abbr, '-', model_forecast_date, '-', measure, '.pdf')
    if(!file.exists(plot_path)) {
      if(measure == 'deaths') {
        data <- covidData::load_jhu_data(
          issue_date = as.character(forecast_week_end_date + 1),
          spatial_resolution = c('state', 'national'),
          temporal_resolution = 'weekly',
          measure = measure) %>%
          dplyr::left_join(fips_codes, by = 'location')
        horizon <- 4L
        types <- c('inc', 'cum')
        required_quantiles <- c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
      } else if(measure == 'cases') {
        data <- covidData::load_jhu_data(
          issue_date = as.character(forecast_week_end_date + 1),
          spatial_resolution = c('county', 'state', 'national'),
          temporal_resolution = 'weekly',
          measure = measure) %>%
          dplyr::left_join(fips_codes, by = 'location')
        horizon <- 8L
        types <- 'inc'
        required_quantiles <- c(0.025, 0.100, 0.250, 0.500, 0.750, 0.900, 0.975)
      }

      results <- results %>%
        dplyr::filter(target_end_date <= UQ(forecast_week_end_date) + 7 * horizon)

      location_batches <- results %>%
        dplyr::filter(grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
        dplyr::distinct(location, location_name) %>%
        dplyr::arrange(nchar(location), location_name) %>%
        dplyr::mutate(
          location_name = factor(location_name, levels = location_name),
          batch = rep(seq_len(ceiling(nrow(.)/30)), each = 30)[seq_len(nrow(.))]
        )

      made_plots <- FALSE
      pdf(plot_path, width=24, height=14)

      for(batch_val in unique(location_batches$batch)) {
        print(batch_val)
        batch_locations <- location_batches$location_name[location_batches$batch == batch_val]
        plottable_predictions <- results %>%
          dplyr::filter(
            location_name %in% batch_locations,
            grepl(substr(measure, 1, nchar(measure) - 1), target)) %>%
          dplyr::mutate(
            endpoint_type = ifelse(quantile < 0.5, 'lower', 'upper'),
            alpha = ifelse(
              endpoint_type == 'lower',
              format(2*quantile, digits=3, nsmall=3),
              format(2*(1-quantile), digits=3, nsmall=3))
          ) %>%
          dplyr::filter(alpha != "1.000") %>%
          dplyr::select(-quantile) %>%
          tidyr::pivot_wider(names_from='endpoint_type', values_from='value')

        for(type in types) {
          type_intervals <- plottable_predictions %>%
            dplyr::filter(location_name %in% batch_locations) %>%
            filter(alpha != "1.000", grepl(UQ(type), target))

          if(nrow(type_intervals) > 0) {
            made_plots <- TRUE
            p <- ggplot() +
              geom_line(data=data %>%
                          dplyr::mutate(date = lubridate::ymd(date)) %>%
                          dplyr::filter(location_name %in% batch_locations),
                        mapping = aes_string(x = "date", y = type, group = "location_name")) +
              geom_point(data=data %>%
                           dplyr::mutate(date = lubridate::ymd(date)) %>%
                           dplyr::filter(location_name %in% batch_locations),
                         mapping = aes_string(x = "date", y = type, group = "location_name")) +
              geom_ribbon(
                data = type_intervals,
                mapping = aes(x = target_end_date,
                              ymin=lower, ymax=upper,
                              fill=alpha)) +
              geom_line(
                data = results %>% dplyr::filter(location_name %in% batch_locations) %>%
                  filter(quantile == 0.5,
                         grepl(UQ(type), target),
                         grepl(substr(measure, 1, nchar(measure) - 1), target)),
                mapping = aes(x = target_end_date, y = value)) +
              geom_point(
                data = results %>% dplyr::filter(location_name %in% batch_locations) %>%
                  filter(quantile == 0.5,
                         grepl(UQ(type), target),
                         grepl(substr(measure, 1, nchar(measure) - 1), target)),
                mapping = aes(x = target_end_date, y = value)) +
              facet_wrap(~location_name, ncol=6, scales = 'free_y') +
              ggtitle(paste(type, measure, as.character(forecast_week_end_date))) +
              theme_bw()
            print(p)
          }
        }
      }
      dev.off()
      if(!made_plots) {
        unlink(plot_path)
      }
    }
  }
}
