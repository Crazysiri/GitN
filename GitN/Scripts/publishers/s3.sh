#!/bin/bash
set -euo pipefail

UPDATES_DIR="${1:?Usage: s3.sh <updates-dir>}"

: "${S3_BUCKET:?Set S3_BUCKET}"
: "${S3_PREFIX:=}"
: "${AWS_REGION:=us-east-1}"

destination="s3://${S3_BUCKET}"
if [ -n "$S3_PREFIX" ]; then
    destination="${destination}/$(echo "$S3_PREFIX" | sed 's#^/*##; s#/*$##')"
fi

aws s3 sync "$UPDATES_DIR" "$destination" --region "$AWS_REGION" --delete
echo "Published updates to ${destination}"
