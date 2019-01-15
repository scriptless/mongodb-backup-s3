#!/bin/bash

MONGODB_HOST=${MONGODB_PORT_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_HOST=${MONGODB_PORT_1_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_PORT=${MONGODB_PORT_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_PORT=${MONGODB_PORT_1_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_USER=${MONGODB_USER:-${MONGODB_ENV_MONGODB_USER}}
MONGODB_PASS=${MONGODB_PASS:-${MONGODB_ENV_MONGODB_PASS}}

S3PATH="s3://$BUCKET/$BACKUP_FOLDER"

[[ ( -n "${ENDPOINT_URL}" ) ]] && ENDPOINT_STR=" --endpoint-url ${ENDPOINT_URL}"
[[ ( -n "${BUCKET_REGION}" ) ]] && REGION_STR=" --region ${BUCKET_REGION}"

[[ ( -z "${MONGODB_USER}" ) && ( -n "${MONGODB_PASS}" ) ]] && MONGODB_USER='admin'

[[ ( -n "${MONGODB_USER}" ) ]] && USER_STR=" --username ${MONGODB_USER}"
[[ ( -n "${MONGODB_PASS}" ) ]] && PASS_STR=" --password ${MONGODB_PASS}"
[[ ( -n "${MONGODB_DB}" ) ]] && DB_STR=" --db ${MONGODB_DB}"

#default value of retained backups
RETAIN_COUNT_STR="7"
[[ ( -n "${RETAIN_COUNT}" ) ]] && [[ ${RETAIN_COUNT} =~ ^[0-9]+$ ]] && RETAIN_COUNT_STR="${RETAIN_COUNT}"

# Export AWS Credentials into env file for cron job
printenv | sed 's/^\([a-zA-Z0-9_]*\)=\(.*\)$/export \1="\2"/g' | grep -E "^export AWS" > /root/project_env.sh
chmod +x /root/project_env.sh

echo "=> Creating backup script"
rm -f /backup.sh
cat <<EOF >> /backup.sh
#!/bin/bash
TIMESTAMP=\`/bin/date +"%Y%m%dT%H%M%S"\`
BACKUP_NAME=\${TIMESTAMP}.dump.gz
S3BACKUP=${S3PATH}\${BACKUP_NAME}

aws configure set default.s3.signature_version s3v4
echo "=> Backup started"
if mongodump --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --archive=\${BACKUP_NAME} --gzip ${EXTRA_OPTS} && aws s3 cp \${BACKUP_NAME} \${S3BACKUP} ${REGION_STR} ${ENDPOINT_STR} && rm \${BACKUP_NAME} ;then
    echo "   > Backup succeeded"
else
    echo "   > Backup failed"
fi
echo "=> Done"
EOF
chmod +x /backup.sh
echo "=> Backup script created"

echo "=> Creating restore script"
rm -f /restore.sh
cat <<EOF >> /restore.sh
#!/bin/bash
if [[( -n "\${1}" )]]; then
    RESTORE_ME=\${1}.dump.gz
else
    RESTORE_ME=\$(aws s3 ls ${S3PATH} ${REGION_STR} ${ENDPOINT_STR} | grep '\.dump\.gz' | sort -r | head -1 | awk '{print \$4}')
fi
S3RESTORE=${S3PATH}\${RESTORE_ME}
aws configure set default.s3.signature_version s3v4
echo "=> Restore database from \${RESTORE_ME}"
if aws s3 cp \${S3RESTORE} \${RESTORE_ME} ${REGION_STR} ${ENDPOINT_STR} && mongorestore --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --drop --archive=\${RESTORE_ME} --gzip && rm \${RESTORE_ME}; then
    echo "   Restore succeeded"
else
    echo "   Restore failed"
fi
echo "=> Done"
EOF
chmod +x /restore.sh
echo "=> Restore script created"

echo "=> Creating list script"
rm -f /listbackups.sh
cat <<EOF >> /listbackups.sh
#!/bin/bash
aws s3 ls ${S3PATH} ${REGION_STR} ${ENDPOINT_STR}
EOF
chmod +x /listbackups.sh
echo "=> List script created"

echo "=> Creating retaing script"
rm -f /retain.sh
cat <<EOF >> /retain.sh
#!/bin/bash
if [[ \$(aws s3 ls ${S3PATH} ${REGION_STR} ${ENDPOINT_STR} | grep '\.dump\.gz' | wc -l) -gt ${RETAIN_COUNT_STR} ]]; then
    echo "retaining backups"
    aws s3 ls ${S3PATH} ${REGION_STR} ${ENDPOINT_STR} | grep '\.dump\.gz' | sort | head -n -${RETAIN_COUNT_STR} |  awk '{print \$4}' | while read line
    do
        if [[ "\$line" ]]; then
            aws s3 rm ${S3PATH}\${line} ${REGION_STR} ${ENDPOINT_STR}
            echo "deleted \$line"
        fi
    done
fi
EOF
chmod +x /retain.sh
echo "=> Retain script created"

ln -s /restore.sh /usr/bin/restore
ln -s /backup.sh /usr/bin/backup
ln -s /listbackups.sh /usr/bin/listbackups
ln -s /retain.sh /usr/bin/retain

touch /mongo_backup.log

if [ -n "${INIT_BACKUP}" ]; then
    echo "=> Creating a backup on startup"
    /backup.sh
fi

if [ -n "${INIT_RETAIN}" ]; then
    echo "=> Puring old backups on startup"
    /retain.sh
fi

if [ -n "${INIT_RESTORE}" ]; then
    echo "=> Restore store from the latest backup on startup"
    /restore.sh
fi

if [ -z "${DISABLE_CRON}" ]; then
    echo "${CRON_TIME} . /root/project_env.sh; /backup.sh >> /mongo_backup.log 2>&1; /retain.sh >> /mongo_backup.log 2>&1" > /crontab.conf
    crontab  /crontab.conf
    echo "=> Running cron job"
    cron && tail -f /mongo_backup.log
fi
