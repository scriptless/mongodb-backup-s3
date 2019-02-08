#!/bin/bash
set -e

# Expected env vars to fill in template. This trick is bash parameter expansion (http://wiki.bash-hackers.org/syntax/pe#display_error_if_null_or_unset)
: ${Z_S3_BUCKET:?} # S3 bucket to store backups, e.g: someproject-db-backup-staging
: ${Z_USER_NAME:?} # username of new user, e.g: mongodb-backup-s3-staging-user

tempFile=`mktemp`
cat << EOJSON > $tempFile
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
        "arn:aws:s3:::$Z_S3_BUCKET",
        "arn:aws:s3:::$Z_S3_BUCKET/*"
      ]
    }
  ]
}
EOJSON

policyName=${Z_USER_NAME}-policy

echo "[INFO] creating policy"
aws iam create-policy \
  --policy-name=$policyName \
  --policy-document file://$tempFile

echo "[INFO] reading policy ARN"
policyArn=$(aws iam list-policies --query "Policies[?PolicyName==\`$policyName\`].[Arn]" --output=text)
if [ -z "$policyArn" ]; then
  echo "[ERROR] could not find ARN for policy with name='$policyName', cannot continue"
  exit 1
fi
echo "[INFO] using policy ARN=$policyArn"

echo "[INFO] creating user"
aws iam create-user \
  --user-name=$Z_USER_NAME

echo "[INFO] attaching policy to user"
aws iam attach-user-policy \
  --user-name=$Z_USER_NAME \
  --policy-arn=$policyArn

echo "[INFO] generating keys for user"
aws iam create-access-key \
  --user-name=$Z_USER_NAME

rm $tempFile
