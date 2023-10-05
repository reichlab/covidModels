This directory contains files to support a containerized Docker version of the COVID-19 baseline model that can be run locally or via AWS ECS.

Docs: TBD. For now, here's a summary from [container-demo-app's README.md](https://github.com/reichlab/container-demo-app/blob/main/README.md):

# `/data` dir

The app expects a volume (either a local Docker one or EFS) to be mounted at `/data` which contains all required GitHub repos: `covidModels`, `covidData`, and `covid19-forecast-hub`.

# Environment variables

The app requires six environment variables to be passed in: `SLACK_API_TOKEN`, `CHANNEL_ID`, `GH_TOKEN`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, and `GIT_CREDENTIALS`

# To build the image

```bash
docker build -f /path-to-this-repo/baseline_model_docker/Dockerfile -t container-demo-app:1.0 .
```

# To run the image locally

```bash
docker run --rm \
  --mount type=volume,src=data_volume,target=/data \
  --env-file /path-to-env-dir/.env \
  container-demo-app:1.0
```

# To publish the image

```bash
docker login -u "reichlab" docker.io
docker tag container-demo-app:1.0 reichlab/container-demo-app:1.0
docker push reichlab/container-demo-app:1.0
```
