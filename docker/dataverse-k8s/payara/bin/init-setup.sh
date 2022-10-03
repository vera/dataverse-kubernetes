#!/bin/bash
################################################################################
# This script is used to configure a Dataverse installation from ...
# It is used solely for changing Database settings!
################################################################################
echo "--" > /tmp/status.log;
until curl -sS -f "http://localhost:8080/robots.txt" -m 2 2>&1 > /dev/null;
    do echo ">>>>>>>> Waiting for Dataverse...." >> /tmp/status.log; echo "---- Dataverse is not ready...." >> /tmp/status.log; sleep 20; done;
    echo "Dataverse is running...But it has no data. Setup initial data.">> /tmp/status.log;
 echo "---Updating reference_data.sql--" >> /tmp/status.log;
 sleep 20;

if [ -s "${HOME_DIR}/dvinstall/reference_data.sql" ]; then
  psql -U ${POSTGRES_USER} -h ${POSTGRES_SERVER} -d ${POSTGRES_DATABASE} -f ${HOME_DIR}/dvinstall/reference_data.sql
fi

DV_SU_PASSWORD="admin"


command -v jq >/dev/null 2>&1 || { echo >&2 '`jq` ("sed for JSON") is required, but not installed. Download the binary for your platform from http://stedolan.github.io/jq/ and make sure it is in your $PATH (/usr/bin/jq is fine) and executable with `sudo chmod +x /usr/bin/jq`. On Mac, you can install it with `brew install jq` if you use homebrew: http://brew.sh . Aborting.'; exit 1; }

#SERVER=http://localhost:8080/api
SERVER=${DATAVERSE_URL}/api

# Everything + the kitchen sink, in a single script
# - Setup the metadata blocks and controlled vocabulary
# - Setup the builtin roles
# - Setup the authentication providers
# - setup the settings (local sign-in)
# - Create admin user and root dataverse
# - (optional) Setup optional users and dataverses

# Check if Dataverse is online
healthcheck="/tmp/healthcheck.log"
curl http://localhost:8080/api/dataverses/root|grep "description" >> $healthcheck
sleep 3

if [ -s $healthcheck ];
then
        echo "Dataverse exists. Skipping setup from scratch..."
else
	# Setup Dataverse if it's empty
	echo "Setup Dataverse from scratch..." >> /tmp/status.log
	cd bash ${HOME_DIR}/dvinstall
	echo "Setup the metadata blocks" >> /tmp/status.log
	bash ${HOME_DIR}/dvinstall/setup-datasetfields.sh

	echo "Setup the builtin roles" >> /tmp/status.log
	bash ${HOME_DIR}/dvinstall/setup-builtin-roles.sh

	echo "Setup the authentication providers" >> /tmp/status.log
	bash ${HOME_DIR}/dvinstall/setup-identity-providers.sh

	bash ${HOME_DIR}/dvinstall/setup-all.sh


	echo "Setting up the admin user (and as superuser)" >> /tmp/status.log
	adminResp=$(curl -s -H "Content-type:application/json" -X POST -d @data/user-admin.json "$SERVER/builtin-users?password=$DV_SU_PASSWORD&key=burrito")
	echo $adminResp
	curl -X POST "$SERVER/admin/superuser/dataverseAdmin"
	echo

	echo "Setting up the root dataverse" >> /tmp/status.log
	adminKey=$(echo $adminResp | jq .data.apiToken | tr -d \")
	curl -s -H "Content-type:application/json" -X POST -d @data/dv-root.json "$SERVER/dataverses/?key=$adminKey"
	echo
	echo "Set the metadata block for Root" >> /tmp/status.log
	curl -s -X POST -H "Content-type:application/json" -d "[\"citation\"]" $SERVER/dataverses/:root/metadatablocks/?key=$adminKey
	echo
	echo "Set the default facets for Root" >> /tmp/status.log
	curl -s -X POST -H "Content-type:application/json" -d "[\"authorName\",\"subject\",\"keywordValue\",\"dateOfDeposit\"]" $SERVER/dataverses/:root/facets/?key=$adminKey
	echo
fi

# Run scripts from init.d folder to finish configuration
if [ "${INIT_SCRIPTS_FOLDER}" ]; then
    for initscript in $INIT_SCRIPTS_FOLDER/0*
        do
           bash "$initscript"
        done
fi

# OPTIONAL USERS AND DATAVERSES
#./setup-optional.sh
#${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} undeploy dataverse
#${PAYARA_DIR}/bin/asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} deploy /opt/payara/dvinstall/dataverse.war

# Apply customization to Bundle.properties and reload application without restart
chown -R payara:payara ${PAYARA_DIR}/glassfish/domains/${DOMAIN_NAME}/applications/dataverse/WEB-INF/classes/propertyFiles/Bundle.properties
if [ "${INIT_SCRIPTS_FOLDER}" ]; then
    for initscript in $INIT_SCRIPTS_FOLDER/2*
        do
           bash "$initscript"
        done
fi
touch ${PAYARA_DIR}/glassfish/domains/${DOMAIN_NAME}/applications/dataverse/.reload
sleep 15

if [ "${INIT_SCRIPTS_FOLDER}" ]; then
    for initscript in $INIT_SCRIPTS_FOLDER/1*
        do
           bash "$initscript"
        done
fi
echo
echo "Setup done. Enjoy Dataversing...." >> /tmp/status.log
