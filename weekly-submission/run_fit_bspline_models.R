library(tidyr)
library(dplyr)
library(lubridate)

cluster_local <- "cluster"
cluster_local <- "local"

required_locations <- readr::read_csv(
  "https://raw.githubusercontent.com/reichlab/covid19-forecast-hub/master/data-locations/locations.csv"
)$location

# combinations of methods and dates for which to predict
analysis_combinations <- tidyr::expand_grid(
  forecast_week_end_date = as.character(
#    lubridate::ymd('2020-05-30') + seq(from = 0, length = 19)*7),
    lubridate::ymd("2020-05-30") + 19*7),
  location = required_locations,
  model = c("local_quad", "damped_local_quad"),
  temporal_resolution = "weekly"
)

# paths where things are saved
if (cluster_local == "cluster") {
  # on cluster
  save_path <- "/project/uma_nicholas_reich/covidModels/forecasts-by-location/"
  output_path <- "/project/uma_nicholas_reich/covidModels/logs/"
  lsfoutfilename <- "covidModels_local_quad_bspline.out"
  covidModels_path <- "/home/er71a/covidModels/"
} else {
  # Evan's computer
  save_path <- "~/research/epi/covid/covidModels/weekly-submission/forecasts-by-location/"
  output_path <- "~/research/epi/covid/covidModels/weekly-submission/logs/"
  lsfoutfilename <- "covidModels_ar_bspline.out"
  covidModels_path <- "~/research/epi/covid/covidModels/"
}

for (row_ind in rev(seq_len(nrow(analysis_combinations)))[1]) {
  forecast_week_end_date <- analysis_combinations$forecast_week_end_date[row_ind]
  location <- analysis_combinations$location[row_ind]
  model <- analysis_combinations$model[row_ind]
  temporal_resolution <- analysis_combinations$temporal_resolution[row_ind]
  full_model_case <- paste0(model, "_bspline_", temporal_resolution)
  
  results_filename <- paste0(save_path,
    model, "_bspline_", temporal_resolution, "/",
    lubridate::ymd(forecast_week_end_date) + 2,
    "-", model, "_bspline_", temporal_resolution,
    "-", location,
    ".csv")
  if(file.exists(results_filename)) {
    print(paste0("Skipping ", results_filename))
  } else {
    if (cluster_local == "cluster") {
      filename <- paste0(output_path, "submit-", full_model_case,
        "_", forecast_week_end_date, "_",
        location,
        ".sh")

      requestCmds <- "#!/bin/bash\n"
      requestCmds <- paste0(requestCmds,
        "#BSUB -n 1 # how many cores we want for our job\n",
        "#BSUB -R span[hosts=1] # ask for all the cores on a single machine\n",
        "#BSUB -R rusage[mem=5000] # ask for memory\n",
        "#BSUB -o ", lsfoutfilename, " # log LSF output to a file\n",
        "#BSUB -W 2:00 # run time\n",
       "#BSUB -q short # which queue we want to run in\n")

      cat(requestCmds, file = filename)
      cat("module load gcc/8.1.0\n", file = filename, append = TRUE)
      cat("module load R/4.0.0_gcc\n", file = filename, append = TRUE)
      cat(paste0("R CMD BATCH --vanilla \'--args ",
          forecast_week_end_date, " ",
          location, " ",
          model, " ",
          temporal_resolution, " ",
          cluster_local, " ",
          "\' ", covidModels_path, "weekly-submission/fit_bspline_model_one_location.R ",
          output_path, "output-", full_model_case, "_",
          forecast_week_end_date, "_",
          location, ".Rout"),
        file = filename, append = TRUE)

      run_cmd <- paste0("bsub < ", filename)
    } else {
      run_cmd <- paste0("R CMD BATCH --vanilla \'--args ",
        forecast_week_end_date, " ",
        location, " ",
        model, " ",
        temporal_resolution, " ",
        cluster_local, " ",
        "\' ", covidModels_path, "weekly-submission/fit_bspline_model_one_location.R ",
        output_path, "/output-", full_model_case,
        forecast_week_end_date, "_",
        location, ".Rout")
    }

    system(run_cmd)
  }
}
