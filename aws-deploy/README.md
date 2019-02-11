These instructions will:
  1. create an ECS cluster (using Fargate, not EC2)
  1. deploy this docker image as a scheduled task
  1. configure a cron schedule to run the task

Fargate is fairly expensive but as we're only running the task infrequently and for a very short time,
the cost should be minimal.

## Steps

  1. optionally, define an AWS CLI profile and region to run in
      ```bash
      export AWS_PROFILE=default        # change me if needed
      export AWS_REGION=ap-southeast-2  # change me if needed
      ```

  1. create a new ECS cluster. You only need one cluster, you can run backups for staging and prod on the same cluster.
      ```bash
      Z_CLUSTER_NAME=cron-fargate-cluster # optionally change me
      aws ecs create-cluster \
        --cluster-name=$Z_CLUSTER_NAME
      ```

  1. create an env var of the `clusterArn` that was returned, we'll need that later
      ```bash
      export Z_CLUSTER_ARN=arn:aws:ecs:ap-southeast-2:123456789123:cluster/cron-fargate-cluster
      ```

  1. you probably run multiple environments (dev, staging, prod, etc) and want to keep backups of a few of
     them. These instructions use a suffix to namespace by environment or *stage*. Let's define that now:
      ```bash
      export Z_STAGE=staging # change me to 'prod' or something else if needed
      ```

  1. create a log group for the ECS task to write to
      ```bash
      export Z_LOG_GROUP_NAME=/ecs/mongodb-backup-s3-logs-$Z_STAGE

      aws logs create-log-group \
        --log-group-name=$Z_LOG_GROUP_NAME
      ```

  1. create an S3 bucket to store the backups in
      ```bash
      export Z_S3_BUCKET=someproject-db-backup-$Z_STAGE # TODO change prefix if needed
      aws s3 mb s3://$Z_S3_BUCKET
      ```

  1. create an IAM policy and user that this container can run as
      ```bash
      export Z_USER_NAME=mongodb-backup-s3-${Z_STAGE}-user # don't change, this user will be created
      ./create-iam-policy-and-user.sh
      ```

  1. grab the access keys from the output of the previous command and export them as env vars
      ```bash
      export Z_AWS_ACCESS_KEY_ID=change-me      # TODO change me
      export Z_AWS_SECRET_ACCESS_KEY=change-me  # TODO change me
      ```

  1. get the ARN for the ECS task execution role. If you don't have this role already, [create
     it](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html)
      ```bash
      export Z_EXECUTION_ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName==\`ecsTaskExecutionRole\`].[Arn]" --output=text) && \
      if [ -z "$Z_EXECUTION_ROLE_ARN" ]; then echo "[ERROR] no role ARN found, you need to create one and re-run this command"; \
      else echo "[INFO] role ARN found, carry on"; fi
      ```

  1. create a new task definition/update (create new revision) of existing definition
      ```bash
      export Z_MONGODB_HOST=SOMECluster-shard-0/somecluster-shard-00-00-no9bo.mongodb.net,somecluster-shard-00-01-no9bo.mongodb.net,somecluster-shard-00-02-no9bo.mongodb.net
                                          # TODO change me to mongo host (single host or cluster), include ports if non-standard
      export Z_MONGODB_DB=someproject     # TODO change me to the name of the DB to backup
      export Z_MONGODB_USER=someuser      # TODO change me to the user to connect as
      export Z_MONGODB_PASS=somepassword  # TODO change me password of the user

      ./create-ecs-task-def.sh
      ```

  1. create an env var from the newly created task ARN, we'll need that later
      ```bash
      export Z_TASK_DEF_ARN=$(aws ecs list-task-definitions --query="taskDefinitionArns[?contains(@, 'mongodb-backup-s3-task-$Z_STAGE') == \`true\`] | [0]" --output=text) && \
      if [ -z "$Z_TASK_DEF_ARN" -o "$Z_TASK_DEF_ARN" == "None" ]; then echo "[ERROR] no task ARN found, you did the previous command work?"; \
      else echo "[INFO] task ARN found, carry on"; fi
      ```

  1. create a schedule (that we'll use to run the task). You can re-run this at a later time to update the
     existing schedule.
      ```bash
      export Z_RULE_NAME=MongoBackup-$Z_STAGE
      Z_CRON_MINUTE_HOUR='0 20' # TODO change me if you want, the format is 'minute hour'
      aws events put-rule \
        --schedule-expression="cron($Z_CRON_MINUTE_HOUR * * ? *)" \
        --name=$Z_RULE_NAME
      ```

  1. get the ARN of the `ecsEventsRole` IAM role that was created for us when we registered the task. If you don't already have
     this role, [create it](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/CWE_IAM_role.html). Be
     sure to also read the section of that page that talks about changing the *trust relationship* from
     `ecs-tasks.amazonaws.com` to `events.amazonaws.com` otherwise nothing will work. See the troubleshooting
     section at the bottom of this document for more info.
      ```bash
      export Z_ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName==\`ecsEventsRole\`].[Arn]" --output=text) && \
      if [ -z "$Z_ROLE_ARN" ]; then echo "[ERROR] no role ARN found, you need to create one and re-run this command"; \
      else echo "[INFO] role ARN found, carry on"; fi
      ```

  1. get the ID of the network security group to deploy into. Use the `GroupId` field of your chosen group
      ```bash
      # run this command to search for groups
      aws ec2 describe-security-groups --query="SecurityGroups[*].{GroupId: GroupId, GroupName: GroupName}"

      # pick a GroupId from the response and export it as an env var
      export Z_SEC_GROUP=sg-changeme # TODO change me
      ```

  1. get the ID of a network subnet to deploy into. Use the `SubnetId` field
      ```bash
      # run this command to search for subnets
      aws ec2 describe-subnets

      # pick a SubnetId from the response and export it as an env var
      export Z_SUBNET=subnet-changeme # TODO change me
      ```

  1. tie the task definition to the event trigger.
      ```bash
      # uses all the env vars we exported earlier
      ./create-event-schedule.sh
      ```

  1. if you see output that looks like the following, you're done
      ```bash
      {
          "FailedEntryCount": 0,
          "FailedEntries": []
      }
      ```

Unless you changed the cron schedule, the job will run once per day. You'll find the backups in the S3 bucket you defined. You can
see logs from the job output in the *Logs* section of CloudWatch. You can see the task we created under the *Scheduled Tasks* tab
for the cluster you created.

# Troubleshooting

## Scheduled task doesn't run and can't be edited in web console
This can be frustrating because there are no logs and no errors, there's no nothing happening.

The role that gets generated automatically when you configure a schedule ECS task via the web console works
correctly but if you followed all the steps above on an account that didn't have the IAM roles existing and
you had to manually create them, then you might have missed some of the steps (that page is hard to read
correctly).

The best indicator that you're experiencing this issue is when you try to edit the scheduled task using the
web console and the first step of performing the update is "Create role". This first step fails (goes red) but
then nothing happens in the web console. If you experience this, the following steps will fix this.

Make sure to read the "To check for the CloudWatch Events IAM role in the IAM console" section on [this
page](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/CWE_IAM_role.html). It tells you how to edit
the *trust relationship* to trust `events.amazonsaws.com` instead of the `ecs-tasks.amazonaws.com` that
happens by default.

Once you've changed that trust relationship, things should start working.
