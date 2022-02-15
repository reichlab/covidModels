This directory contains [AWS](https://aws.amazon.com/) -based scripts that automate the running of weekly utility scripts in this repo.


# Files
- README.md: this file
- baseline-setup.md: sketch of the commands that configured the instance - libraries, etc.
- lambda.py: the Lambda function
- run-baseline.sh: runs the Reichlab COVID-19 model
- run-startup-script.sh: the instance's init script that runs on startup. dispatches based on the "startup_script" tag (see below)
- run-weekly-reports.sh: runs the Reichlab COVID-19 reports generator. dispatches based on ""
- sandbox.sh: a debugging script that does some git operations and posts Slack messages and uploads a file to slack
- slack.sh: defines some simple functions for posting slack messages and uploading files


# Manually starting a run
You can start any particular script manually via the [AWS console](https://console.aws.amazon.com/console/home) by following these steps:
- Go to the [runCovidWeekly](https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions/runCovidWeekly?tab=code) AWS Lambda page.
- Using the "Test" dropdown, select the run you'd like to do and then click "Test".
- Note that the "noop" test will *not* cause the instance to shut down once the test finishes, so you'll have to manually stop it yourself. All the other tests will cause a shutdown.


# GitHub configuration: `reichlabmachine` account
To support automation access to the relevant GitHub repos, we created a GitHub "machine user" account named [reichlabmachine](https://github.com/reichlabmachine/) and owned by Nick. That account's GitHub personal access token (PAT) is what's used to do writes (e.g., `push`es) to the repos. It was stored via `git config credential.helper store`.


# AWS configuration
These scripts require a somewhat involved setup of multiple AWS services, along with a Slack application configuration. Following are configuration details.

AWS account: You'll need admin access to manage the resources listed below. Contact [Nick](https://reichlab.io/) for that.


# Script startup
We use a single EC2 instance to run any of the scripts. This means we must be able to configure the script at runtime to choose which script to run. We decided to pass this information via a special instance tag with the key "startup_script" and with a value of the name (*not* the full path) one of the `*.sh` scripts in this directory . For debugging, you may use `sandbox.sh`. Any value that is not an existing script name will be ignored. By convention, we use "none". Note that all of the scripts shut down the machine when done.

The "startup_script" key value can be set manually for debugging, but is primarily set by the Lambda function (see below) which takes the script name via JSON passed to it. The JSON is an object with a single "startup_script" key and a value as above. This allows us to use a single Lambda function that is configured by the AWS EventBridge event that runs it. For example:
```json
{"startup_script": "sandbox.sh"}
```


## steps to set up the instance to run `run-startup-script.sh`
- Enable tag access in the instance following these steps: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html#allow-access-to-tags-in-IMDS .
- Add a tag with the key "startup_script" as described above.
- Set the user data to the following, all of which is basically [cloud-init](https://cloudinit.readthedocs.io/en/latest/topics/datasources/ec2.html) boilerplate except the `su` line at the bottom:
```bash
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash
su -c "/data/covidModels/aws-vm-scripts/run-startup-script.sh" ec2-user >> /tmp/startup-out.txt 2>&1
--//--
```

# AWS EC2 instance
I’ve configured this EC2 instance: [i-0db5237193478dd8d](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#InstanceDetails:instanceId=i-0db5237193478dd8d), which is named "baseline model". It is an [Amazon Linux 2](https://aws.amazon.com/amazon-linux-2/) machine that has been configured to have all the required settings and OS and R libraries. It auto-mounts (via `fstab`) a 100 GB [gp2 EBS volume](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html) that has clones of the required repos, and persists across reboots.

The instance's account is the default `ec2-user`, which is the owner of the EBS volume's cloned repos.


# AWS Lambda function
The Lambda function [start-baseline-instance](https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions/start-baseline-instance?tab=code) (written in Python) starts the above EC2 instance, looking for the instance whose name is 'baseline model' to identify it. The function's execution role is [EC2RoleForBaselineScriptLambda](https://console.aws.amazon.com/iam/home#/roles/EC2RoleForBaselineScriptLambda?section=permissions), which has the [EC2DescribeStartStopWithLogs](https://console.aws.amazon.com/iam/home#/policies/arn:aws:iam::312560106906:policy/EC2DescribeStartStopWithLogs$jsonEditor) policy attached to it. That policy allows describing, starting, and stopping instances, and writing to logs.


# AWS EventBridge events
We have set up Amazon EventBridge rules to run the Lambda function on a schedule, specifying which script to start up as described above.

Rules:
- [MondayMorning9aEST](https://console.aws.amazon.com/events/home?region=us-east-1#/eventbus/default/rules/MondayMorning9aEST): triggers the Lambda function that starts the above EC2 instance, using the cron event schedule `cron(0 9 ? * MON *)` (every Monday at 9AM EST). Passes "run-baseline.sh" for "startup_script".
- [TuesdayMorning930aEST](https://us-east-1.console.aws.amazon.com/events/home?region=us-east-1#/eventbus/default/rules/TuesdayMorning930aEST): Similar to "", but runs every Tuesday at 9:30AM EST. Passes "run-weekly-reports.sh" for "startup_script". 


## Slack app
`run-baseline.sh` uses the Slack app [baseline script app](https://reichlab.slack.com/apps/A031PAEB2TA-baseline-script-app?settings=1&tab=settings) (developer configuration link [here](https://api.slack.com/apps/A031PAEB2TA)) to communicate status and results while it's running.

App credentials and channel information are passed to the script via the `~ec2-user/.env` file, which contains these fields:

```bash
SLACK_API_TOKEN=xoxb-...
CHANNEL_ID=C01DTCAL49X
```

The token is the _Bot User OAuth Token_ for the app, and the channel id is that of [#weekly-ensemble](https://app.slack.com/client/T089JRGMA/C01DTCAL49X). The app has been configured to have the `chat:write` and `files:write` _Bot Token Scopes_, and has been added to that channel.

For simplicity, we use simple `curl` calls ([docs](https://api.slack.com/tutorials/tracks/posting-messages-with-curl)) to send messages and upload files - see the functions `slack_message()` and `slack_upload()` in `run-baseline.sh`.

