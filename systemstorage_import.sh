#!/bin/bash -e

# Get absolute path to main directory
MY_PATH=`dirname $(readlink -f "$0")`
RELEASEFOLDER=$(readlink -f "${MY_PATH}/../../..")
DOCUMENTROOT=htdocs
SYSTEMSTORAGEPATH=${RELEASEFOLDER}/../backup
SOURCE_DIR="${RELEASEFOLDER}/tools"
DATABASETYPE=dev

function usage {
    echo "Usage:"
    echo "$0 [-s <systemStoragePath>] where to read the system storage (optional defaults to <releasefolder>/../backup"
    echo "   [-d <documentRoot>] the document root (optional, defaults to htdocs)"
    echo "   [-f] restore full backup instead of dev "
    echo ""
    echo "Example:"
    echo "    -s /media/tmp/<projekt>/<backup> -d web-site"
    exit $1
}

# Process options
while getopts 's:d:f' OPTION ; do
    case "${OPTION}" in
        d) DOCUMENTROOT=`echo "${OPTARG}" | sed -e "s/\/*$//" `;; # delete last slash
        s) SYSTEMSTORAGEPATH=`echo "${OPTARG}" | sed -e "s/\/*$//" `;; # delete last slash
        f) DATABASETYPE=full;;
    esac
done

PROJECT_WEBROOT="${RELEASEFOLDER}/${DOCUMENTROOT}"

if [ ! -d "${PROJECT_WEBROOT}" ] ; then echo "Could not find project root ${PROJECT_WEBROOT}" ; usage 1; fi
if [ ! -f "${PROJECT_WEBROOT}/index.php" ] ; then echo "Invalid ${PROJECT_WEBROOT} (could not find index.php)" ; usage 1; fi


if [ ! -f "${SYSTEMSTORAGEPATH}/${DATABASETYPE}.sql.gz" ]; then echo "Could not find database dump ${SYSTEMSTORAGEPATH}/${DATABASETYPE}.sql.gz"; usage 1; fi;

n98="/usr/bin/php -d apc.enable_cli=0 ${SOURCE_DIR}/n98-magerun --root-dir=${PROJECT_WEBROOT}"

# Importing database...
echo "Dropping all tables"
$n98 -q db:drop --tables --force || { echo "Error while dropping all tables"; exit 1; }

echo "Import database dump ${SYSTEMSTORAGEPATH}/${DATABASETYPE}.sql.gz"
$n98 -q db:import --compression=gzip "${SYSTEMSTORAGEPATH}/${DATABASETYPE}.sql.gz" ||  { echo "Error while importing dump"; exit 1; }

if [ ! -f "${SYSTEMSTORAGEPATH}/shared.tgz" ]; then echo "Could not find shared.tgz"; usage 1; fi;

# restore shared
SHAREDBASE="${RELEASEFOLDER}/../shared"
if [ ! -d "${SHAREDBASE}" ] ; then
    echo "Could not find '../shared'. Trying '../../shared' now"
    SHAREDBASE="${RELEASEFOLDER}/../../shared"
    if [ ! -d "${SHAREDBASE}" ] ; then
        echo "Could not find '../../shared'. Trying '../../../shared' now"
        SHAREDBASE="${RELEASEFOLDER}/../../../shared";
        if [ ! -d "${SHAREDBASE}" ]; then
            SHAREDBASE="${RELEASEFOLDER}/${DOCUMENTROOT}"
        fi
    fi
fi

cd $SHAREDBASE;

if [ -f "${RELEASEFOLDER}/Configuration/shared.txt" ]; then
    for target in `cat ${RELEASEFOLDER}/Configuration/shared.txt`; do
        if [[ ${target} != "var" ]]; then
            if [[ ${LIST} == "" ]]; then
                LIST=${target}
            else
                LIST="${LIST} ${target}"
            fi
        fi
    done
else
    LIST="media"
fi

pwd
echo "Deleting ${LIST}"
rm -rf ${LIST}

echo "Extracting shared.tgz"
tar -xzf ${SYSTEMSTORAGEPATH}/shared.tgz