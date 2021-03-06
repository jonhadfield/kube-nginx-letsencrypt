#!/bin/bash

if [[ -z $EMAIL || -z $DOMAINS || -z $SECRETNAME ]]; then
	echo "EMAIL, DOMAINS and SECRETNAME env vars required"
	exit 1
fi

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

echo "Requesting certificates for:"
echo "  EMAIL: $EMAIL"
echo "  DOMAINS: $DOMAINS"
echo "  NAMESPACE: $NAMESPACE"
echo "  PODS: $NGINX_PODS"

echo "Creating env file"
cat /hooks/.env-template | sed "s/ACME_SECRETNAME_TEMPLATE/${ACME_SECRETNAME}/" | sed "s/NAMESPACE_TEMPLATE/${NAMESPACE}/" > /hooks/.env

echo "Requesting certificate"
certbot certonly --manual --preferred-challenges http -n --agree-tos --email ${EMAIL} --no-self-upgrade -d ${DOMAINS} --manual-public-ip-logging-ok --manual-auth-hook /hooks/authenticator.sh

echo "Verifying path to certificate exists"
tree /etc/letsencrypt

BASE_CERTPATH=/etc/letsencrypt/live
MAIN_DOMAIN=$(echo $DOMAINS | cut -f1 -d',')

CERTPATH="$BASE_CERTPATH/$MAIN_DOMAIN/fullchain.pem"
KEYPATH="$BASE_CERTPATH/$MAIN_DOMAIN/privkey.pem"
ls $CERTPATH $KEYPATH || exit 1

echo "Renewal config /etc/letencrypt/renewal/$MAIN_DOMAIN.conf"
cat /etc/letencrypt/renewal/$MAIN_DOMAIN.conf

ls /ssl-secret-patch-template.json || exit 1

echo "SSL secret patch file exists. Executing template"
cat /ssl-secret-patch-template.json | sed "s/SECRETNAMESPACE/${NAMESPACE}/" | sed "s/SECRETNAME/${SECRETNAME}/" | sed "s/TLSCERT/$(cat ${CERTPATH} | base64 | tr -d '\n')/" | sed "s/TLSKEY/$(cat ${KEYPATH} |  base64 | tr -d '\n')/" > /ssl-secret-patch.json

echo "Updating certificate secret '$SECRETNAME'"
curl -i --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -XPATCH  -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" -d @/ssl-secret-patch.json https://kubernetes.default.svc/api/v1/namespaces/${NAMESPACE}/secrets/${SECRETNAME}

if [[ $NGINX_PODS != "" ]]; then
	echo "Waiting 30 seconds before restarting nginx pods"
	sleep 30
	
	NGINX_PODS=$(echo $NGINX_PODS | sed 's/,/ /')
	for NGINX_POD in $NGINX_PODS
	do
		echo "Restarting ${NGINX_POD} pod"
		curl -i --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k -XPOST  -H "Accept: */*" https://kubernetes.default.svc/api/v1/namespaces/${NAMESPACE}/pods/${NGINX_POD}/exec?command=service&command=nginx&command=restart
	done
fi
