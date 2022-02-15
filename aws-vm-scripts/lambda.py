import boto3


STARTUP_SCRIPT_KEY = 'startup_script'
BASELINE_INSTANCE_NAME = 'covid weekly'  # as tagged in instance


def lambda_handler(event, context):
    """
    Lambda function that configures and starts a Reichlab weekly script as documented at
    https://github.com/reichlab/covidModels/blob/master/aws-vm-scripts/README.md .

    :param event: a dict that specifies which script the instance should run. format: (see link above). a dict that
        contains a single key named 'startup_script' and whose value is the name (not path) of the aws-vm-scripts script
        to run. ex: {'startup_script': 'sandbox.sh'}
    :param context:
    :return:
    """
    print(f"entered. event={event}, context={context}")

    # validate event
    if isinstance(event, dict) and (STARTUP_SCRIPT_KEY in event):
        startup_script = event[STARTUP_SCRIPT_KEY]
        print(f"found startup_script={startup_script!r}")
    else:
        startup_script = 'none'  # our no-op convention
        print(f"startup_script not found. defaulting to startup_script={startup_script!r}")

    # find and start the instance
    ec2_resource = boto3.resource('ec2', 'us-east-1')
    filters = [{'Name': 'tag:Name', 'Values': [BASELINE_INSTANCE_NAME]}]
    instances = ec2_resource.instances.filter(Filters=filters)
    print(f"starting found instance(s)")
    for instance in instances:
        print(f"instance={instance}. setting startup_script tag. key={STARTUP_SCRIPT_KEY!r}, value={startup_script!r}")
        instance.create_tags(Tags=[{'Key': STARTUP_SCRIPT_KEY, 'Value': startup_script}])
        print(f"starting: {instance}. tags={instance.tags}")  # tags=[{'Key': 'Name', 'Value': 'covid weekly'}, {'Key': 'startup_script', 'Value': 'run-weekly-reports.shxx'}]
        instance.start()
    print(f"done")
