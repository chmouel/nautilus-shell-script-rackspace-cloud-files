#!/bin/bash
ARGS=$@

function get_api_key {
    RCLOUD_API_USER=$(zenity --title "Enter Username" --entry \
        --text "Rackspace Cloud Username:" --width 200 --height 50)
    [[ -z $RCLOUD_API_USER ]] && exit 1 #press cancel
    RCLOUD_API_KEY=$(zenity --title "Enter Username" --entry \
        --text "Rackspace Cloud API Key:" --width 200 --height 50)
    [[ -n ${RCLOUD_API_KEY} && -n ${RCLOUD_API_USER} ]] || {
        zenity --title "Missing Username/API Key" --error --text \
            "You have not specified a Rackspace Cloud username or API key" \
            --width 200 --height 25;
        exit 1;
    }
    check_api_key
    mkdir -p ${HOME}/.config/rackspace-cloud
    echo "RCLOUD_API_USER=${RCLOUD_API_USER}" > ${HOME}/.config/rackspace-cloud/config
    echo "RCLOUD_API_KEY=${RCLOUD_API_KEY}" >> ${HOME}/.config/rackspace-cloud/config
}

function check_api_key {
    temp_file=$(mktemp /tmp/.rackspace-cloud.XXXXXX)
    local good_key=
    curl -s -f -D - \
      -H "X-Auth-Key: ${RCLOUD_API_KEY}" \
      -H "X-Auth-User: ${RCLOUD_API_USER}" \
      https://auth.api.rackspacecloud.com/v1.0 >${temp_file} && good_key=1

    if [[ -z $good_key ]];then
        zenity --title "Bad Username/API Key" --error --text \
            "Cannot identify with your Rackspace Cloud username or API key" \
            --width 200 --height 25;
        exit 1;
    fi

    while read line;do
        [[ $line != X-* ]] && continue
        line=${line#X-}
        key=${line%: *};key=${key//-/}
        value=${line#*: }
        value=$(echo ${value}|sed 's/\r$//')
        eval "export $key=$value"
    done < ${temp_file}

    rm -f ${temp_file}
}

function create_container {
    local container=$1

    if [[ -z $container ]];then
        zenity --title "Need a container name" --error --text \
            "You need to specify a container name" \
            --width 200 --height 25;
        exit 1;
    fi

    created=
    curl -f -k -X PUT -D - \
      -H "X-Auth-Token: ${AuthToken}" \
      ${StorageUrl}/${container} && created=1

    if [[ -z $container ]];then
        zenity --title "Cannot create container" --error --text \
            "Cannot create container name ${container}" \
            --width 200 --height 25;
        exit 1;
    fi
}

function put_object {
    local container=$1
    local file=$(readlink -f $2)
    local object=$(basename ${file})
    #url encode in sed yeah i am not insane i have googled that
    object=$(echo $object|sed -e 's/%/%25/g;s/ /%20/g;s/ /%09/g;s/!/%21/g;s/"/%22/g;s/#/%23/g;s/\$/%24/g;s/\&/%26/g;s/'\''/%27/g;s/(/%28/g;s/)/%29/g;s/\*/%2a/g;s/+/%2b/g; s/,/%2c/g; s/-/%2d/g; s/\./%2e/g; s/:/%3a/g; s/;/%3b/g; s//%3e/g; s/?/%3f/g; s/@/%40/g; s/\[/%5b/g; s/\\/%5c/g; s/\]/%5d/g; s/\^/%5e/g; s/_/%5f/g; s/`/%60/g; s/{/%7b/g; s/|/%7c/g; s/}/%7d/g; s/~/%7e/g; s/      /%09/g;')
    
    if [[ ! -e ${file} ]];then
        zenity --title "Cannot find file" --error --text \
            "Cannot find file ${file}" \
            --width 200 --height 25;
        exit 1
    fi

    local etag=$(md5sum ${file});etag=${etag%% *} #TODO progress
    local ctype=$(file -bi ${file});ctype=${ctype%%;*}
    if [[ -z ${ctype} || ${ctype} == *corrupt* ]];then
        ctype="application/octet-stream"
    fi
    
    uploaded=
    curl -o/dev/null -f -X PUT -T ${file} \
        -H "ETag: ${etag}" \
        -H "Content-type: ${ctype}" \
        -H "X-Auth-Token: ${StorageToken}" \
        ${StorageUrl}/${container}/${object} 2>&1|zenity --text "Uploading ${object}"  --title "Uploading" \
        --width 500 --height 50 \
        --progress --pulsate --auto-kill --auto-close
}

function choose_container {
    lastcontainer=
    if [[ -e ${HOME}/.config/rackspace-cloud/last-container ]];then
        lastcontainer=$(cat ${HOME}/.config/rackspace-cloud/last-container)
    fi
    
    CONTAINERS_LIST=$(curl -s -f -k -X GET \
      -H "X-Auth-Token: ${AuthToken}" \
      ${StorageUrl}|sort -n
    )
    args=
    for cont in ${CONTAINERS_LIST};do
        v=FALSE
        if [[ $cont == ${lastcontainer} ]];then
            v=TRUE
        fi
        args="$args ${v} ${cont}"
    done
    
    container=$(zenity  --height=500 --list --title "Which Container"  --text "Which Container you want to upload?" --radiolist  \
        --column "Pick" --column "Container" $args
    )
    mkdir -p ${HOME}/.config/rackspace-cloud
    echo ${container} > ${HOME}/.config/rackspace-cloud/last-container
    echo $container
}

[[  -e ${HOME}/.config/rackspace-cloud/config ]] && \
    source ${HOME}/.config/rackspace-cloud/config
[[ -n ${RCLOUD_API_KEY} && -n ${RCLOUD_API_USER} ]] && check_api_key || get_api_key

container=$(choose_container)

set -u
set -e

IFS=""
for file in $@;do
    file=$(readlink -f ${file})
    [[ -e ${file} ]] || continue
    put_object ${container} ${file}
done
