#!/bin/bash -e

# Get absolute path to main directory
MY_PATH=`dirname $(readlink -f "$0")`
RELEASEFOLDER=$(readlink -f "${MY_PATH}/../../..")
DOCUMENTROOT=htdocs
SYSTEMSTORAGEPATH=${RELEASEFOLDER}/../backup
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

# archive shared
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

LIST=""

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

OLD=`pwd`
cd ${SHAREDBASE}
tar -czf ${SYSTEMSTORAGEPATH}/shared.tgz \
    --exclude-vcs \
    --exclude=media/catalog/product/cache/* \
    --exclude=media/tmp/* \
    --exclude=media/js/* \
    --exclude=media/css/* \
    --exclude=media/css_secure/* \
     ${LIST}

cd ${OLD}

