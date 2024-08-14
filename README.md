# mongodb-backup-s3

This image runs `mongodump` to backup data to an AWS S3 bucket. It can be run on a cron timer or
immediately when the container is launched.

We support custom S3 compatable storage by providing your own endpoint.

Limiting the (configurable) number of retained backups is also supported.

## Forked from [ternandsparrow/mongodb-backup-s3](https://github.com/ternandsparrow/mongodb-backup-s3)

This fork adds:

- Replace MongoDB variables with MONGODB_URI
- Add variables EXTRA_OPTS_MONGO and EXTRA_OPTS_AWS to replace EXTRA_OPTS
- Add storage class option for aws command

## Usage:

```
docker run -d \
  --env AWS_ACCESS_KEY_ID=awsaccesskeyid \
  --env AWS_SECRET_ACCESS_KEY=awssecretaccesskey \
  --env BUCKET=mybucketname \
  --env MONGODB_URI=uri \
  --env RETAIN_COUNT=5 \
  docker.scriptless.io/mongodb-backup-s3:latest
```

If your bucket is not in a standard region and you get `A client error (PermanentRedirect) occurred
when calling the PutObject operation: The bucket you are attempting to access must be addressed
using the specified endpoint. Please send all future requests to this endpoint` use `BUCKET_REGION`
env var like this (assume your region is `ap-southeast-2`):

```
docker run -d \
  --env AWS_ACCESS_KEY_ID=myaccesskeyid \
  --env AWS_SECRET_ACCESS_KEY=mysecretaccesskey \
  --env BUCKET=mybucketname \
  --env BUCKET_REGION=ap-southeast-2 \
  --env BACKUP_FOLDER=a/sub/folder/path/ \
  --env INIT_BACKUP=true \
  docker.scriptless.io/mongodb-backup-s3:latest
```

Add to a `docker-compose.yml` to enhance your robotic army:

For automated backups

```
mongodbbackup:
  image: 'docker.scriptless.io/mongodb-backup-s3:latest'
  links:
    - mongodb
  environment:
    - AWS_ACCESS_KEY_ID=myaccesskeyid
    - AWS_SECRET_ACCESS_KEY=mysecretaccesskey
    - BUCKET=my-s3-bucket
    - BACKUP_FOLDER=prod/db/
    - ENDPOINT_URL=https://s3.example.com
    - RETAIN_COUNT=5
  restart: always
```

Or use `INIT_RESTORE` with `DISABLE_CRON` for seeding/restoring/starting a db (great for a fresh instance or a dev machine)

```
mongodbbackup:
  image: 'docker.scriptless.io/mongodb-backup-s3:latest'
  links:
    - mongodb
  environment:
    - AWS_ACCESS_KEY_ID=myaccesskeyid
    - AWS_SECRET_ACCESS_KEY=mysecretaccesskey
    - BUCKET=my-s3-bucket
    - BACKUP_FOLDER=prod/db/
    - INIT_RESTORE=true
    - DISABLE_CRON=true
```

## Running on AWS ECS Fargate

See the instructions in [aws-deploy/README.md](./aws-deploy/README.md).

## Example AWS IAM policy

This policy contains the required permissions for this container to operate. Replace the
`YOUR-BUCKET-HERE` placeholder with your bucket name.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-BUCKET-HERE",
        "arn:aws:s3:::YOUR-BUCKET-HERE/*"
      ]
    }
  ]
}
```

## Parameters

`AWS_ACCESS_KEY_ID` - your aws access key id (for your s3 bucket)

`AWS_SECRET_ACCESS_KEY`: - your aws secret access key (for your s3 bucket)

`AWS_STORAGE_CLASS`: - sets the storage class

`BUCKET`: - your s3 bucket

`BUCKET_REGION`: - your s3 bucket' region (eg `us-east-2` for Ohio). Optional. Add if you get an error `A client error (PermanentRedirect)`

`ENDPOINT_URL`: - your custom S3 endpoint (eg `https://radosgw.example.com` )

`BACKUP_FOLDER`: - name of folder or path to put backups (eg `myapp/db_backups/`). defaults to root of bucket.

`MONGODB_URI` - the uri of your mongodb database

`EXTRA_OPTS_MONGO` - any extra options to pass to mongodump command

`EXTRA_OPTS_AWS` - any extra options to pass to aws command

`CRON_TIME` - the interval of cron job to run mongodump. `0 3 * * *` by default, which is every day at 03:00hrs.

`TZ` - timezone. default: `Europe/Berlin`

`CRON_TZ` - cron timezone. default: `Europe/Berlin`

`INIT_BACKUP` - if set, create a backup when the container launched

`INIT_RESTORE` - if set, restore from latest when container is launched

`INIT_RETAIN` - if set, purge old backups when container is launched (will run after backup if `INIT_BACKUP` is set)

`DISABLE_CRON` - if set, it will skip setting up automated backups. good for when you want to use this container to seed a dev environment.

`RETAIN_COUNT` - how many backups should be kept. `7` by default.

## Restore from a backup

Note, all these commands expect that the contain is already running (cron is enabled).
The commands will exec into the existing container to run the command.

To see the list of backups, you can run:

```
docker exec mongodb-backup-s3 /listbackups.sh
```

To restore database from a certain backup, simply run (pass in just the timestamp part of the filename):

```
docker exec mongodb-backup-s3 /restore.sh 20170406T155812
```

To restore latest just:

```
docker exec mongodb-backup-s3 /restore.sh
```

## Acknowledgements

Fork tree

```
https://github.com/halvves/mongodb-backup-s3
 └─ https://github.com/deenoize/mongodb-backup-s3
    └─ https://github.com/chobostar/mongodb-backup-s3
       └─ https://github.com/zhonghuiwen/mongodb-backup-s3
          └─ https://github.com/ternandsparrow/mongodb-backup-s3
            └─ https://github.com/k-t-corp/mongodb-backup-s3'
                └─ this fork
```
