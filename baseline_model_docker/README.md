This directory contains files to support a containerized Docker version of the COVID-19 baseline model that can be run locally or via AWS ECS.

Docs: TBD. For now, here's a summary from [baseline-model's README.md](https://github.com/reichlab/baseline-model/blob/main/README.md):

# `/data` dir

The app expects a volume (either a local Docker one or EFS) to be mounted at `/data` which contains all required GitHub repos: `covidModels`, `covidData`, and `covid19-forecast-hub`.

Note: This project's `Dockerfile`s run the script version mounted under `/data/covidModels` , which means you need to update that repo after editing and pushing scripts for the changes to be picked up. To explore the volume:

```bash
# (optional) explore the volume from the command line via a temp container
docker run --rm -it --name temp_container --mount type=volume,src=data_volume,target=/data ubuntu /bin/bash

# if you need git installed:
apt update ; apt install -y git
```

# Environment variables

The app requires six environment variables to be passed in: `SLACK_API_TOKEN`, `CHANNEL_ID`, `GH_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, and `GIT_CREDENTIALS`

# To build the image

```bash
cd "path-to-this-repo/baseline_model_docker"
docker build -t baseline-model:1.0 .
```

# To run the image locally

```bash
docker run --rm \
  --mount type=volume,src=data_volume,target=/data \
  --env-file /path-to-env-dir/.env \
  baseline-model:1.0
```

# To publish the image

```bash
docker login -u "reichlab" docker.io
docker tag baseline-model:1.0 reichlab/baseline-model:1.0
docker push reichlab/baseline-model:1.0
```
