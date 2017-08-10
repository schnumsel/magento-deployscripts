#!/bin/bash

VALID_ENVIRONMENTS=" production staging devbox latest deploy integration stage qa "

MY_PATH=`dirname $(readlink -f "$0")`
RELEASEFOLDER=$(readlink -f "${MY_PATH}/../../..")
DOCUMENTROOT=htdocs
SYSTEM_STORAGE_PATH=${RELEASEFOLDER}/../backup

function safeLink {

    if [ -d "${SHAREDFOLDER}/$1" ]; then
        if [ -d "${RELEASEFOLDER}/${DOCUMENTROOT}/$1" ]; then
            echo "${SHAREDFOLDER}/$1 and ${RELEASEFOLDER}/${DOCUMENTROOT}/$1 exist, removing later.."
            rm -rf ${RELEASEFOLDER}/${DOCUMENTROOT}/$1
        fi
        else
            if [ -d ${RELEASEFOLDER}/${DOCUMENTROOT}/$1 ]; then
                echo "Moving ${RELEASEFOLDER}/${DOCUMENTROOT}/$1 to ${SHAREDFOLDER}/$1"
                mv ${RELEASEFOLDER}/${DOCUMENTROOT}/$1 ${SHAREDFOLDER}/$1
            else
                echo "Neither ${RELEASEFOLDER}/${DOCUMENTROOT}/$1 nor ${SHAREDFOLDER}/$1 exists.."
                exit 1;
            fi
    fi

    echo "Linking ${RELEASEFOLDER}/${DOCUMENTROOT}/$1 to ${SHAREDFOLDER}/$1"
    ln -s "${SHAREDFOLDER}/$1" "${RELEASEFOLDER}/${DOCUMENTROOT}/$1"  || { echo "Error while linking to shared media directory" ; exit 1; }

}

function usage {
    echo "Usage:"
    echo " $0 -e <environment> [-r <releaseFolder>] [-d <documentRoot> ] [-a <masterSystem>] "
    echo "            [-y <systemStorageBasePath>] [-p <project>]".
    echo "            [-Y <systemStorageRootPath>] [-s] [-m] [-c]"
    echo " -e Environment (mandatory e.g. production, staging, devbox,...)"
    echo " -r releaseFolder (optional,different release folder, other than project root)"
    echo " -d documentRoot (optional, different document root, other than htdocs)"
    echo " -a masterSystem (optional, if different than settings in Configuration/mastersystem.txt)"
    echo " -y systemStoragePath (optional, if different than ../backup)"
    echo " -p project (optional, if different than settings in Configuration/project.txt)"
    echo " -s If set the systemstorage will not be imported"
    echo " -c If set shared folder settings will not be applied"
    echo " -m If set modman will not be aplied, use for production and staging if build is prepared without symlinks"
    echo ""
    exit $1
}

while getopts 'e:r:d:a:y:p:scm' OPTION ; do
case "${OPTION}" in
        e) ENVIRONMENT="${OPTARG}";;
        a) MASTER_SYSTEM="${OPTARG}";;
        r) RELEASEFOLDER=`echo "${OPTARG}" | sed -e "s/\/*$//" `;; # delete last slash
        d) DOCUMENTROOT=`echo "${OPTARG}" | sed -e "s/\/*$//" `;;
        y) SYSTEM_STORAGE_PATH=`echo "${OPTARG}" | sed -e "s/\/*$//" `;;
        p) PROJECT="${OPTARG}";;
        s) SKIPIMPORTFROMSYSTEMSTORAGE=true;;
        c) SKIPSHAREDFOLDERCONFIG=true;;
        m) SKIPMODMAN=true;;
        \?) echo; usage 1;;
    esac
done

if [ ! -f "${RELEASEFOLDER}/${DOCUMENTROOT}/index.php" ] ; then echo "Invalid release folder" ; exit 1; fi
if [ ! -f "${RELEASEFOLDER}/tools/n98-magerun" ] ; then echo "Could not find n98-magerun" ; exit 1; fi
if [ ! -f "${RELEASEFOLDER}/tools/apply.php" ] ; then echo "Could not find apply.php" ; exit 1; fi
if [ ! -f "${RELEASEFOLDER}/Configuration/settings.csv" ] ; then echo "Could not find settings.csv" ; exit 1; fi

# Checking environment
if [ -z "${ENVIRONMENT}" ]; then echo "ERROR: Please provide an environment code (e.g. -e staging)"; exit 1; fi
if [[ "${VALID_ENVIRONMENTS}" =~ " ${ENVIRONMENT} " ]] ; then
    echo "Environment: ${ENVIRONMENT}"
else
    echo "ERROR: Illegal environment code" ; exit 1;
fi

echo
echo "Linking to shared directories"
echo "-----------------------------"
if [[ -n ${SKIPSHAREDFOLDERCONFIG} ]]  && ${SKIPSHAREDFOLDERCONFIG} ; then
    echo "Skipping shared directory config because parameter was set"
else

    # Added one level lower, so shared folder can be on the same level as project folder (ww)
    SHAREDFOLDER="${RELEASEFOLDER}/../shared"
    if [ ! -d "${SHAREDFOLDER}" ] ; then
        echo "Could not find '../shared'. Trying '../../shared' now"
        SHAREDFOLDER="${RELEASEFOLDER}/../../shared"
        if [ ! -d "${SHAREDFOLDER}" ] ; then
            echo "Could not find '../../shared'. Trying '../../../shared' now"
            SHAREDFOLDER="${RELEASEFOLDER}/../../../shared";
        fi
    fi

    if [ ! -d "${SHAREDFOLDER}" ] ; then echo "Shared directory ${SHAREDFOLDER} not found"; exit 1; fi

    safeLink media
    safeLink var
fi

echo
echo "Running modman"
echo "--------------"
if [[ -n ${SKIPMODMAN} ]]  && ${SKIPMODMAN} ; then
    echo "Skipping modman because parameter was set"
else
    cd "${RELEASEFOLDER}" || { echo "Error while switching to release directory" ; exit 1; }
    tools/modman deploy-all --force || { echo "Error while running modman" ; exit 1; }
fi

echo
echo "Systemstorage"
echo "-------------"
if [[ -n ${SKIPIMPORTFROMSYSTEMSTORAGE} ]]  && ${SKIPIMPORTFROMSYSTEMSTORAGE} ; then
    echo "Skipping import system storage backup because parameter was set"
else

    if [ -z "${MASTER_SYSTEM}" ] ; then
        if [ ! -f "${RELEASEFOLDER}/Configuration/mastersystem.txt" ] ; then echo "Could not find mastersystem.txt"; exit 1; fi
        MASTER_SYSTEM=`cat ${RELEASEFOLDER}/Configuration/mastersystem.txt`
        if [ -z "${MASTER_SYSTEM}" ] ; then echo "Error reading master system"; exit 1; fi
    fi

    if [ "${MASTER_SYSTEM}" == "${ENVIRONMENT}" ] ; then
        echo "Current environment is the master environment. Skipping import."
    else
        echo "Current environment is not the master environment. Importing system storage..."

        if [ -z "${PROJECT}" ] ; then
            if [ ! -f "${RELEASEFOLDER}/Configuration/project.txt" ] ; then echo "Could not find project.txt"; exit 1; fi
            PROJECT=`cat ${RELEASEFOLDER}/Configuration/project.txt`
            if [ -z "${PROJECT}" ] ; then echo "Error reading project name"; exit 1; fi
        fi

        # Apply db settings
        cd "${RELEASEFOLDER}/${DOCUMENTROOT}" || { echo "Error while switching to ${DOCUMENTROOT} directory" ; exit 1; }
        ../tools/apply.php "${ENVIRONMENT}" ../Configuration/settings.csv --groups db || { echo "Error while applying db settings" ; exit 1; }


        # Import systemstorage
        ../tools/systemstorage_import.sh -p "${RELEASEFOLDER}/${DOCUMENTROOT}/" -s "${SYSTEM_STORAGE_PATH}" || { echo "Error while importing systemstorage"; exit 1; }
    fi

fi

echo
echo "Applying settings"
echo "-----------------"
cd "${RELEASEFOLDER}/${DOCUMENTROOT}" || { echo "Error while switching to ${DOCUMENTROOT} directory" ; exit 1; }
../tools/apply.php ${ENVIRONMENT} ../Configuration/settings.csv || { echo "Error while applying settings" ; exit 1; }
echo

if [ -f "${RELEASEFOLDER}/${DOCUMENTROOT}/shell/aoe_classpathcache.php" ] ; then
    echo
    echo "Setting revalidate class path cache flag (Aoe_ClassPathCache)"
    echo "-------------------------------------------------------------"
    cd "${RELEASEFOLDER}/${DOCUMENTROOT}/shell" || { echo "Error while switching to ${DOCUMENTROOT}/shell directory" ; exit 1; }
    php aoe_classpathcache.php -action setRevalidateFlag || { echo "Error while revalidating Aoe_ClassPathCache" ; exit 1; }
fi

echo
echo "Triggering Magento setup scripts via n98-magerun"
echo "------------------------------------------------"
cd -P "${RELEASEFOLDER}/${DOCUMENTROOT}/" || { echo "Error while switching to ${DOCUMENTROOT} directory" ; exit 1; }
../tools/n98-magerun.phar sys:setup:run || { echo "Error while triggering the update scripts using n98-magerun" ; exit 1; }

echo
echo "Cache"
echo "-----"

if [ "${ENVIRONMENT}" == "devbox" ] || [ "${ENVIRONMENT}" == "latest" ] || [ "${ENVIRONMENT}" == "deploy" ] ; then
    cd -P "${RELEASEFOLDER}/${DOCUMENTROOT}/" || { echo "Error while switching to ${DOCUMENTROOT} directory" ; exit 1; }
    ../tools/n98-magerun cache:flush || { echo "Error while flushing cache using n98-magerun" ; exit 1; }
    ../tools/n98-magerun cache:enable || { echo "Error while enabling cache using n98-magerun" ; exit 1; }
fi


if [ -f "${RELEASEFOLDER}/${DOCUMENTROOT}/maintenance.flag" ] ; then
    echo
    echo "Deleting maintenance.flag"
    echo "-------------------------"
    rm "${RELEASEFOLDER}/${DOCUMENTROOT}/maintenance.flag" || { echo "Error while deleting the maintenance.flag" ; exit 1; }
fi

echo
echo "Successfully completed installation."
echo
