#!/usr/bin/env bash

MYSELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

if [ -z "${CERTBOT_DOMAIN}" ]; then
  mkdir -p "${PWD}/letsencrypt"

  certbot certonly \
    --non-interactive \
    --manual \
    --manual-auth-hook "${MYSELF}" \
    --manual-cleanup-hook "${MYSELF}" \
    --preferred-challenge dns \
    --config-dir "${PWD}/letsencrypt" \
    --work-dir "${PWD}/letsencrypt" \
    --logs-dir "${PWD}/letsencrypt" \
    "$@"

else
  [[ ${CERTBOT_AUTH_OUTPUT} ]] && ACTION="DELETE" || ACTION="UPSERT"

  DOMAIN="${CERTBOT_DOMAIN}"
  while [ -z "${HOSTED_ZONE_ID}" ] && [ -n "${DOMAIN}" ]; do
    printf -v QUERY 'HostedZones[?Name == `%s.`].Id' "${DOMAIN}"

    HOSTED_ZONE_ID="$(aws route53 list-hosted-zones --query "${QUERY}" --output text)"

    DOMAIN="$(sed -r 's/^[^.]+.(.*)$/\1/' <<< "${DOMAIN}")"
  done

  if [ -z "${HOSTED_ZONE_ID}" ]; then
    if [ -n "${DOMAIN}" ]; then
      echo "No hosted zone found that matches domain ${DOMAIN} or hostname ${CERTBOT_DOMAIN}"
    else
      echo "No hosted zone found that matches ${CERTBOT_DOMAIN}"
    fi
    exit 1
  fi

  aws route53 wait resource-record-sets-changed --id "$(
    aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --query ChangeInfo.Id --output text \
    --change-batch "{
      \"Changes\": [{
        \"Action\": \"${ACTION}\",
        \"ResourceRecordSet\": {
          \"Name\": \"_acme-challenge.${CERTBOT_DOMAIN}.\",
          \"ResourceRecords\": [{\"Value\": \"\\\"${CERTBOT_VALIDATION}\\\"\"}],
          \"Type\": \"TXT\",
          \"TTL\": 30
        }
      }]
    }"
  )"

  echo 1
fi
