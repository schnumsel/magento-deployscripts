#!/bin/bash -e

# Get absolute path to main directory
MY_PATH=`dirname $(readlink -f "$0")`
RELEASEFOLDER=$(readlink -f "${MY_PATH}/../../..")
DOCUMENTROOT=htdocs
SYSTEMSTORAGEPATH=${RELEASEFOLDER}/../../backup
SOURCE_DIR="${RELEASEFOLDER}/tools"
DOCUMENTROOT=htdocs

function usage {
    echo "Usage:"
    echo "$0 [-s <systemStoragePath>] where to write the system storage (optional defaults to <releasefolder>/../backup"
    echo "   [-d <documentRoot>] the document root (optional, defaults to htdocs)"
    echo ""
    echo "Example:"
    echo "    -s /media/tmp/<projekt>/<backup> -d web-site"
    exit $1
}


# Process options
while getopts 's:d:' OPTION ; do
    case "${OPTION}" in
        d) DOCUMENTROOT=`echo "${OPTARG}" | sed -e "s/\/*$//" `;; # delete last slash
        s) SYSTEMSTORAGEPATH=`echo "${OPTARG}" | sed -e "s/\/*$//" `;; # delete last slash
    esac
done

PROJECT_WEBROOT="${RELEASEFOLDER}/${DOCUMENTROOT}"

if [ ! -d "${PROJECT_WEBROOT}" ] ; then echo "Could not find project root ${PROJECT_WEBROOT}" ; usage 1; fi
if [ ! -f "${PROJECT_WEBROOT}/index.php" ] ; then echo "Invalid ${PROJECT_WEBROOT} (could not find index.php)" ; usage 1; fi

if [ ! -d "${SYSTEMSTORAGEPATH}" ] ; then echo "Could not find systemstorage path  $SYSTEMSTORAGEPATH" ; usage 1; fi

# magerun
n98="/usr/bin/php -d apc.enable_cli=0 ${SOURCE_DIR}/n98-magerun --root-dir=${PROJECT_WEBROOT}"

# export db
$n98 db:dump --compression=gz --strip="@stripped @development" ${SYSTEMSTORAGEPATH}/dev.sql.gz
$n98 db:dump --compression=gz ${SYSTEMSTORAGEPATH}/full.sql.gz

# archive media
# find media folder

MEDIAFOLDER="${RELEASEFOLDER}/../../shared/media"
if [ ! -d "${MEDIAFOLDER}" ] ; then
    echo "Could not find '../../shared/media'. Trying '../../../shared/media' now"
    MEDIAFOLDER="${RELEASEFOLDER}/../../../shared/media";
    if [ ! -d "${SHAREDFOLDER}" ]; then
        MEDIAFOLDER="${RELEASEFOLDER}/${DOCUMENTROOT}/media"
    fi
fi

if [ ! -d "${MEDIAFOLDER}" ] ; then echo "Media folder ${MEDIAFOLDER} not found"; exit 1; fi

OLD=`pwd`
cd ${MEDIAFOLDER}
tar -czf ${SYSTEMSTORAGEPATH}/media.tgz .
cd ${OLD}

