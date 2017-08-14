#!/bin/bash -e

# Get absolute path to main directory
MY_PATH=`dirname $(readlink -f "$0")`
RELEASEFOLDER=$(readlink -f "${MY_PATH}/../../..")
DOCUMENTROOT=htdocs
SYSTEMSTORAGEPATH=${RELEASEFOLDER}/../../backup
SOURCE_DIR="${RELEASEFOLDER}/tools"
DOCUMENTROOT=htdocs
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

n98="/usr/bin/php -d apc.enable_cli=0 ${SOURCE_DIR}/n98-magerun.phar --root-dir=${PROJECT_WEBROOT}"

# Importing database...
echo "Dropping all tables"
$n98 -q db:drop --tables --force || { echo "Error while dropping all tables"; exit 1; }

echo "Import database dump ${SYSTEMSTORAGEPATH}/${DATABASETYPE}.sql.gz"
$n98 -q db:import --compression=gzip "${SYSTEMSTORAGEPATH}/${DATABASETYPE}.sql.gz" ||  { echo "Error while importing dump"; exit 1; }

TMPDIR=`mktemp -d`
OLD=`pwd`
cd TMPDIR


echo "Extract media folder"
tar -xzf "${SYSTEMSTORAGEPATH}/media.tgz"

echo "Sync media folder"

rsync \
    --archive \
    --force \
    --no-o --no-p --no-g \
    --omit-dir-times \
    --ignore-errors \
    --partial \
    --exclude=/catalog/product/cache/ \
    --exclude=/tmp/ \
    --exclude=.svn/ \
    --exclude=*/.svn/ \
    --exclude=.git/ \
    --exclude=*/.git/ \
    "${TMPDIR}/" "${PROJECT_WEBROOT}/media/"

cd ${OLD}

echo "Remove temp folder"
rm -rf ${TMPDIR}

echo "Finished importing system storage"