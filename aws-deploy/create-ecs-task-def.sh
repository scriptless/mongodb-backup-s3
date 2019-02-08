#!/bin/bash
# creates a Task Definition in AWS ECS for this docker image
set -e

imageVersion=1.2.2
region=ap-southeast-2
# Expected env vars to fill in template. This trick is bash parameter expansion (http://wiki.bash-hackers.org/syntax/pe#display_error_if_null_or_unset)
: ${Z_EXECUTION_ROLE_ARN:?} # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html, e.g: arn:aws:iam::123456789123:role/ecsTaskExecutionRole
: ${Z_LOG_GROUP_NAME:?} # e.g: /ecs/mongodb-backup-s3-logs-staging
: ${Z_STAGE:?} # the stage name, e.g: 'staging' or 'prod'
: ${Z_S3_BUCKET:?} # S3 bucket to store backups, e.g: someproject-db-backup-staging
Z_RETAIN_COUNT=${Z_RETAIN_COUNT:-4} # number of backups to retain, e.g: 4
: ${Z_MONGODB_HOST:?} # e.g: SOMECluster-shard-0/somecluster-shard-00-00-no9bo.mongodb.net,somecluster-shard-00-01-no9bo.mongodb.net,somecluster-shard-00-02-no9bo.mongodb.net
: ${Z_MONGODB_DB:?} # the name of the database to backup, e.g: someproject-staging
: ${Z_MONGODB_USER:?} # username for the MongoDB connection
: ${Z_MONGODB_PASS:?} # password for the MongoDB user
: ${Z_AWS_ACCESS_KEY_ID:?} # for a user who can write to the S3 bucket
: ${Z_AWS_SECRET_ACCESS_KEY:?} # for a user who can write to the S3 bucket

tempFile=`mktemp`
cat << EOJSON > $tempFile
{
  "family": "mongodb-backup-s3-task-$Z_STAGE",
  "networkMode": "awsvpc",
  "executionRoleArn": "$Z_EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "ternandsparrow_mongodb-backup-s3",
      "cpu": 0,
      "image": "ternandsparrow/mongodb-backup-s3:$imageVersion",
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$Z_LOG_GROUP_NAME",
          "awslogs-stream-prefix": "ecs",
          "awslogs-region": "$region"
        }
      },
      "environment": [
        {
          "name": "TZ",
          "value": "Australia/Adelaide"
        }, {
          "name": "AWS_ACCESS_KEY_ID",
          "value": "$Z_AWS_ACCESS_KEY_ID"
        }, {
          "name": "AWS_SECRET_ACCESS_KEY",
          "value": "$Z_AWS_SECRET_ACCESS_KEY"
        }, {
          "name": "BUCKET",
          "value": "$Z_S3_BUCKET"
        }, {
          "name": "RETAIN_COUNT",
          "value": "$Z_RETAIN_COUNT"
        }, {
          "name": "MONGODB_HOST",
          "value": "$Z_MONGODB_HOST"
        }, {
          "name": "BUCKET_REGION",
          "value": "$region"
        }, {
          "name": "MONGODB_PORT",
          "value": "27017"
        }, {
          "name": "INIT_BACKUP",
          "value": "true"
        }, {
          "name": "EXTRA_OPTS",
          "value": "--ssl --authenticationDatabase admin"
        }, {
          "name": "DISABLE_CRON",
          "value": "true"
        }, {
          "name": "INIT_RETAIN",
          "value": "true"
        }, {
          "name": "MONGODB_DB",
          "value": "$Z_MONGODB_DB"
        }, {
          "name": "MONGODB_USER",
          "value": "$Z_MONGODB_USER"
        }, {
          "name": "MONGODB_PASS",
          "value": "$Z_MONGODB_PASS"
        }
      ],
      "essential": true
    }
  ],
  "requiresCompatibilities": [
    "FARGATE"
  ],
  "cpu": "512",
  "memory": "1024"
}
EOJSON

aws ecs register-task-definition --cli-input-json file://$tempFile

rm $tempFile
