FROM rocker/tidyverse

RUN apt update && apt install -y curl gpg
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg;
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null;
RUN apt update && apt install -y gh;

RUN Rscript -e "install.packages(c('furrr', 'ggpubr', 'googledrive', 'here', 'plotly', 'tictoc', 'yaml', 'zeallot'))"
RUN Rscript -e "devtools::install_github('reichlab/covidData')"
RUN Rscript -e "devtools::install_github('reichlab/covidEnsembles')"
RUN Rscript -e "devtools::install_github('reichlab/covidHubUtils')"

# NB: during developement we require this repo's `baseline_model_docker` branch to be checked out in the mounted volume
CMD ["bash", "/data/covidModels/ensemble_model_docker/run-ensemble.sh"]
