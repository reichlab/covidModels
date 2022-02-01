This directory contains [AWS](https://aws.amazon.com/) -based scripts that automate the running of model-building scripts in this repo.


# GitHub configuration
To support automation access to the relevant GitHub repos, we created a GitHub "machine user" account named [reichlabmachine](https://github.com/reichlabmachine/) and owned by Nick. That account's GitHub personal access token (PAT) is what's used to do writes (e.g., `push`es) to the repos. It was stored via `git config credential.helper store`.


# AWS configuration
These scripts require a somewhat involved setup of multiple AWS services, along with a Slack application configuration. Following are configuration details for each script.

AWS account: You'll need admin access to manage the resources listed below. Contact [Nick](https://reichlab.io/) for that.


# sandbox.sh
This is a simple debugging script that tests 1) access to the Slack app, and 2) access to the reichlabmachine [sandbox repo](https://github.com/reichlabmachine/sandbox) for writes.


# run-baseline.sh
Following are the components involved.


## Manually starting a run
One can manually invoke a `run-baseline` run by simply starting the below EC2 instance from the AWS EC2 console. It will run the script when the machine is up, and then the script will stop the instance when it's done.


## AWS EC2 instance
I’ve configured an EC2 instance to run the Bash script `run-baseline.sh` when the VM starts up. The instance is: [i-0db5237193478dd8d](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#InstanceDetails:instanceId=i-0db5237193478dd8d) and is named "baseline model". It is an [Amazon Linux 2](https://aws.amazon.com/amazon-linux-2/) machine that has been configured to have all the required settings and OS and R libraries. It auto-mounts (via `fstab`) a 100 GB [gp2 EBS volume](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html) that has clones of the required repos, and persists across reboots. `run-baseline.sh` shuts down the machine at the end of its run, so the workflow is to simply start the instance, which will then run the script and shut down.

The instance's account is the default `ec2-user`, which is the owner of the EBS volume's cloned repos.

To do development on the instance, first edit its user data script (scroll to the bottom) to comment out the call `run-baseline`. Then start the instance, do your development, stop the instance, and then re-edit the user data to restore the script call. The `sandbox.sh` script may be useful for debugging.


### AWS EC2 user data script
The [cloud-init](https://cloudinit.readthedocs.io/en/latest/topics/datasources/ec2.html) script that's run when the instance starts is:

```html
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
su -c "~ec2-user/run-baseline.sh" ec2-user >> /tmp/startup-out.txt
--//--
```

The last line is the one you can temporarily comment out or replace for development work (see below).


## AWS EventBridge event
The Amazon EventBridge rule [MondayMorning9aEST](https://console.aws.amazon.com/events/home?region=us-east-1#/eventbus/default/rules/MondayMorning9aEST) triggers the below Lambda function that starts the above EC2 instance, using the cron event schedule `cron(0 9 ? * MON *)` (every Monday at 9AM EST).


## AWS Lambda function
The Lambda function [start-baseline-instance](https://console.aws.amazon.com/lambda/home?region=us-east-1#/functions/start-baseline-instance?tab=code) (written in Python) starts the above EC2 instance, looking for the instance whose name is 'baseline model' to identify it. The function's execution role is [EC2RoleForBaselineScriptLambda](https://console.aws.amazon.com/iam/home#/roles/EC2RoleForBaselineScriptLambda?section=permissions), which has the [EC2DescribeStartStopWithLogs](https://console.aws.amazon.com/iam/home#/policies/arn:aws:iam::312560106906:policy/EC2DescribeStartStopWithLogs$jsonEditor) policy attached to it. That policy allows describing, starting, and stopping instances, and writing to logs.


### Lambda function code
The actual Python code is straightforward:

```python
import boto3


def lambda_handler(event, context):
    print(f"entered. event={event}, context={context}")
    ec2_resource = boto3.resource('ec2', 'us-east-1')
    filters = [{'Name': 'tag:Name', 'Values': ['baseline model']}]
    instances = ec2_resource.instances.filter(Filters=filters)
    print(f"starting any instances")
    for instance in instances:
        print(f"starting: {instance}. tags={instance.tags}")  # [{'Key': 'Name', 'Value': 'baseline model'}]
        instance.start()
    print(f"done")
```


## Slack app
`run-baseline.sh` uses the Slack app [baseline script app](https://reichlab.slack.com/apps/A031PAEB2TA-baseline-script-app?settings=1&tab=settings) (developer configuration link [here](https://api.slack.com/apps/A031PAEB2TA)) to communicate status and results while it's running.

App credentials and channel information are passed to the script via the `~ec2-user/.env` file, which contains these fields:

```bash
SLACK_API_TOKEN=xoxb-...
CHANNEL_ID=C01DTCAL49X
```

The token is the _Bot User OAuth Token_ for the app, and the channel id is that of [#weekly-ensemble](https://app.slack.com/client/T089JRGMA/C01DTCAL49X). The app has been configured to have the `chat:write` and `files:write` _Bot Token Scopes_, and has been added to that channel.

For simplicity, we use simple `curl` calls ([docs](https://api.slack.com/tutorials/tracks/posting-messages-with-curl)) to send messages and upload files - see the functions `slack_message()` and `slack_upload()` in `run-baseline.sh`.
