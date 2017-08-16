#!/bin/bash

VALID_ENVIRONMENTS=" production staging devbox latest deploy integration stage qa "

MY_PATH=`dirname $(readlink -f "$0")`
RELEASEFOLDER=$(readlink -f "${MY_PATH}/../../..")
DOCUMENTROOT=htdocs
SYSTEM_STORAGE_PATH=${RELEASEFOLDER}/../backup

function normalizePath {

    # Remove all /./ sequences.
    local path=${1//\/.\//\/}

    # Remove dir/.. sequences.
    while [[ $path =~ ([^/][^/]*/\.\./) ]]
    do
        path=${path/${BASH_REMATCH[0]}/}
    done
    echo $path
}

function realPath {

    local HERE=$PWD
    if [ -d $1 ]; then
        cd $1
        THERE=$( pwd -P )
        echo ${THERE}
    fi
    cd ${HERE}

}

function relativePath {

    # both $1 and $2 are absolute paths beginning with /
    # returns relative path to $2/$target from $1/$source
    source=$1
    target=$2

    common_part=$source # for now
    result="" # for now

    while [[ "${target#$common_part}" == "${target}" ]]; do
        # no match, means that candidate common part is not correct
        # go up one level (reduce common part)
        common_part="$(dirname $common_part)"
        # and record that we went back, with correct / handling
        if [[ -z $result ]]; then
            result=".."
        else
            result="../$result"
        fi
    done

    if [[ $common_part == "/" ]]; then
        # special case for root (no common path)
        result="$result/"
    fi

    # since we now have identified the common part,
    # compute the non-common part
    forward_part="${target#$common_part}"

    # and now stick all parts together
    if [[ -n $result ]] && [[ -n $forward_part ]]; then
        result="$result$forward_part"
    elif [[ -n $forward_part ]]; then
        # extra slash removal
        result="${forward_part:1}"
    fi

    echo $result
}

function safeLink {

    local shared=$( normalizePath ${SHAREDFOLDER}/$1 )
    local linked=$( normalizePath ${RELEASEFOLDER}/${DOCUMENTROOT}/$1 )

    local shared_base=$( dirname $shared )
    local linked_base=$( dirname $linked )

    local dir_name=$( basename $1)

    #if shared folder exists
    if [ -d "${shared}" ]; then

        # if folder also exist in document root
        # remove folder in document root
        if [ -d "${linked}" ]; then
            echo "Shared ($shared) and linked (${linked}) folders exist, removing linked.."
            rm -rf ${linked}
        fi

    # if shared folder does not exists
    else

        # if folder exists in document root
        if [ -d ${linked} ]; then
            echo "Moving existing linked folder (${linked}) to shared folder (${shared})"
            if [ ! -d ${shared_base} ]; then
                mkdir -p ${shared_base}
            fi
            mv ${linked} ${shared_base}
        else
            echo "Neither shared (${shared}) nor linked folder (${linked}) exist, verify your configuration"
            exit 1;
        fi
    fi


    echo

    if [ ! -d ${linked_base} ]; then
        "mkdir -p ${linked_base}"
    fi

    local real_linked_base=$( realPath "${linked_base}" )

    rel_path=$( relativePath "${real_linked_base}" "${shared}" )

    HERE=${PWD}
    cd ${real_linked_base}
    ln -sf ${rel_path} . || { echo "Error while linking to shared media directory" ; exit 1; }
    cd ${HERE}
}


function usage {
    echo "Usage:"
    echo " $0 -e <environment> [-r <releaseFolder>] [-d <documentRoot> ] [-a <masterSystem>] "
    echo "            [-y <systemStorageBasePath>] [-p <project>]".
    echo "            [-Y <systemStorageRootPath>] [-s] [-c]"
    echo " -e Environment (mandatory e.g. production, staging, devbox,...)"
    echo " -r releaseFolder (optional,different release folder, other than project root)"
    echo " -d documentRoot (optional, different document root, other than htdocs)"
    echo " -a masterSystem (optional, if different than settings in Configuration/mastersystem.txt)"
    echo " -y systemStoragePath (optional, if different than ../backup)"
    echo " -p project (optional, if different than settings in Configuration/project.txt)"
    echo " -s If set the systemstorage will not be imported"
    echo " -c If set shared folder settings will not be applied"
    echo ""
    exit $1
}

while getopts 'e:r:d:a:y:p:sc' OPTION ; do
case "${OPTION}" in
        e) ENVIRONMENT="${OPTARG}";;
        a) MASTER_SYSTEM="${OPTARG}";;
        r) RELEASEFOLDER=`echo "${OPTARG}" | sed -e "s/\/*$//" `;; # delete last slash
        d) DOCUMENTROOT=`echo "${OPTARG}" | sed -e "s/\/*$//" `;;
        y) SYSTEM_STORAGE_PATH=`echo "${OPTARG}" | sed -e "s/\/*$//" `;;
        p) PROJECT="${OPTARG}";;
        s) SKIPIMPORTFROMSYSTEMSTORAGE=true;;
        c) SKIPSHAREDFOLDERCONFIG=true;;
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

    if [ -f "${RELEASEFOLDER}/Configuration/shared.txt" ]; then
        for target in `cat ${RELEASEFOLDER}/Configuration/shared.txt`; do
            echo "Linking $target to document root";
            safeLink $target
        done
    fi
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
        ../tools/systemstorage_import.sh -d "${DOCUMENTROOT}/" -s "${SYSTEM_STORAGE_PATH}" || { echo "Error while importing systemstorage"; exit 1; }
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
../tools/n98-magerun sys:setup:run || { echo "Error while triggering the update scripts using n98-magerun" ; exit 1; }

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
