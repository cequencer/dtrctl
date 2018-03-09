#!/bin/bash
# Mainly used for copying Docker images from DTR 2.0.1 to DTR 2.3.4
# Some things may need to be changed for newer versions of the DTR

# Exit if anything fails
set -e

main() {
    echo "Starting dtrctl ..."
    authenticate

    if [ "$PULL" ]; then
        if [ ! $SRC_DTR_URL ]; then
            echo "error: No source DTR specified"
            exit 1
        fi
  
        getOrgs
        getRepos
        #getTeams
        #getTeamMembers
        #getTeamRepoAccess
        echo "Sync from source DTR to local copy complete"
    fi

    if [ "$PUSH" ]; then
        if [ ! $DEST_DTR_URL ]; then
            echo "error: No destination DTR specified"
            exit 1
        fi

        putOrgs
        putRepos
        #putTeams
        #putTeamMembers
        #putTeamRepoAccess
        echo "Sync from local copy to destination DTR complete"

    fi

    if [ "$SYNC_IMAGES" ]; then
        migrateImages
        echo "Image migration from source DTR to destination DTR complete"
    fi

    if [ "$COMPARE" ]; then
        if [ ! $SRC_DTR_URL ]; then
            echo "error: No source DTR specified"
            exit 1
        elif [ ! $DEST_DTR_URL ]; then
            echo "error: No destination DTR specified"
            exit 1
        else
            checkRepositories
        fi
    fi

    if [ "$PRINT_ACCESS" ]; then
        printAccessMap
    fi
    
    if [ "$INVADER" ]; then
        if [ ! $SRC_DTR_URL ]; then
            echo "error: No source DTR specified"
            exit 1
        elif [ ! $DEST_DTR_URL ]; then
            echo "error: No destination DTR specified"
            exit 1
        else
            migrateAccountImages $USER
        fi
    fi

    if [ "$ALL" ]; then
        if [ ! $SRC_DTR_URL ]; then
            echo "error: No source DTR specified"
            exit 1
        fi
        getOrgs
        getRepos
        
        if [ ! $DEST_DTR_URL ]; then
            echo "error: No destination DTR specified"
            exit 1
        fi
        putOrgs
        putRepos

        migrateImages
    fi
}

authenticate() {
    
    if [ $SRC_DTR_URL ]; then
        if [ ! -d "/etc/docker/certs.d/${SRC_DTR_URL}" ]; then
            mkdir -p /etc/docker/certs.d/"${SRC_DTR_URL}"
        fi

        #curl -ksf https://"${SRC_DTR_URL}"/ca > /etc/docker/certs.d/"${SRC_DTR_URL}"/ca.crt
        #openssl s_client -host "${SRC_DTR_URL}" -port 443 </dev/null 2>/dev/null | openssl x509 -outform PEM > /etc/docker/certs.d/"${SRC_DTR_URL}"/ca.crt

        docker login "$SRC_DTR_URL" -u "$SRC_DTR_USER" -p "$SRC_DTR_PASSWORD"
        SRC_DTR_TOKEN=$(cat ~/.docker/config.json | jq -r '.auths["$SRC_DTR_URL"].identitytoken')
    fi

    if [ $DEST_DTR_URL ]; then
        if [ ! -d "/etc/docker/certs.d/${DEST_DTR_URL}" ]; then
            mkdir -p /etc/docker/certs.d/"${DEST_DTR_URL}"
        fi

        #curl -ksf https://"${DEST_DTR_URL}"/ca > /etc/docker/certs.d/"${DEST_DTR_URL}"/ca.crt
        #openssl s_client -host "${DEST_DTR_URL}" -port 443 </dev/null 2>/dev/null | openssl x509 -outform PEM > /etc/docker/certs.d/"${DEST_DTR_URL}"/ca.crt

        docker login "$DEST_DTR_URL" -u "$DEST_DTR_USER" -p "$DEST_DTR_PASSWORD"
        DEST_DTR_TOKEN=$(cat ~/.docker/config.json | jq -r '.auths["$DEST_DTR_URL"].identitytoken')
    fi
}

########################### 
#             GET         #
###########################

getOrgs() {
    curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
    https://"$SRC_DTR_URL"/enzi/v0/accounts?limit="$SRC_NO_OF_ACCOUNTS" | \
    jq -c '.accounts[] | select(.isOrg==false) | {name: .name, fullName: .fullName, isOrg: .isOrg}' \
    > ../dtrsync/orgConfig

    cat ../dtrsync/orgConfig | jq -r '.name' > ../dtrsync/orgList

    cat ../dtrsync/orgList | while IFS= read -r i;
    do
        if [ ! -d ../dtrsync/$i ]; then
            mkdir ../dtrsync/$i
        fi
    done
}

getRepos() {
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
        https://"$SRC_DTR_URL"/api/v0/repositories/$i?limit="$SRC_NO_OF_REPOS" | \
        jq '.repositories[] | {name: .name, shortDescription: .shortDescription, longDescription: "", visibility: .visibility}' \
        > ../dtrsync/$i/repoConfig
    done
}

############################################################################
#                                                                          #
#  Can ignore the Team methods for now. We are not using teams within DTR  #
#                                                                          #
############################################################################
getTeams() {
    echo "getTeams.."
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
        https://"$SRC_DTR_URL"/enzi/v0/accounts/$i/teams?refresh_token="$SRC_DTR_TOKEN" | jq -c '.teams[] | {name: .name, description: .description}' > ./$i/teamConfig

        cat ./$i/teamConfig | while IFS= read -r j;
        do     
            if [ ! -d ./$i/$(echo $j | jq -r '.name') ]; then
                mkdir ./$i/$(echo $j | jq -r '.name')
            fi
        done
    done
}

getTeamMembers() {
    echo "getTeamMembers.."
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        cat ./$i/teamConfig | jq -r '.name' | while IFS= read -r j;
        do
            curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
            https://"$SRC_DTR_URL"/enzi/v0/accounts/${i}/teams/${j}/members?refresh_token="$SRC_DTR_TOKEN" | jq -c '.members[] | {name: .member.name, isAdmin: .isAdmin, isPublic: .isPublic}' \
            > ./$i/$j/members
        done
    done
}

getTeamRepoAccess() {
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        cat ./$i/teamConfig | jq -r '.name' | while IFS= read -r j;
        do
            curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
            https://"$SRC_DTR_URL"/api/v0/accounts/${i}/teams/${j}/repositoryAccess?refresh_token="$SRC_DTR_TOKEN" | jq -c '.repositoryAccessList[]' \
            > ./$i/$j/repoAccess
        done
    done
}

########################### 
#             PUT         #
###########################

putOrgs() {
    cat ../dtrsync/orgConfig | while IFS= read -r i;
    do
        len=${#i}
        curl -u "$DEST_DTR_USER":"$DEST_DTR_PASSWORD" --insecure \
        -X POST --header "Content-Type: application/json" \
        --header "Accept: application/json" \
        -d "${i:0:$len-1},\"isActive\":true,\"password\":\"$DEST_DTR_PASSWORD\"}" \
        https://"$DEST_DTR_URL"/enzi/v0/accounts?refresh_token="$DEST_DTR_TOKEN"
    done
}

putRepos() {
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        cat ../dtrsync/$i/repoConfig | jq -c '.' | while IFS= read -r j;
        do
            curl -u "$DEST_DTR_USER":"$DEST_DTR_PASSWORD" --insecure \
            -X POST --header "Content-Type: application/json" \
            --header "Accept: application/json" -d "$j" \
            https://"$DEST_DTR_URL"/api/v0/repositories/${i}?refresh_token="$DEST_DTR_TOKEN"
        done
    done
}


############################################################################
#                                                                          #
#  Can ignore the Team methods for now. We are not using teams within DTR  #
#                                                                          #
############################################################################
putTeams() {
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
        https://"$SRC_DTR_URL"/enzi/v0/accounts/$i/teams?refresh_token="$SRC_DTR_TOKEN" | jq -c '.teams[] | {name: .name, description: .description}' > ./$i/teamConfig

        cat ./$i/teamConfig | while IFS= read -r j;
        do
            curl -u "$DEST_DTR_USER":"$DEST_DTR_PASSWORD" --insecure -X POST --header "Content-Type: application/json" \
                --header "Accept: application/json" -d "$j" https://"$DEST_DTR_URL"/enzi/v0/accounts/${i}/teams?refresh_token="$DEST_DTR_TOKEN"
        done
    done

}

putTeamMembers() {
    #Responds with 200 even though team members already exist (I guess this is because of PUT)
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        cat ./$i/teamConfig | jq -r '.name' | while IFS= read -r j;
        do
            cat ./$i/$j/members | while IFS= read -r k;
            do
                teamMemberName=$(echo $k | jq -c -r .name)
                curl -u "$DEST_DTR_USER":"$DEST_DTR_PASSWORD" --insecure -X PUT --header "Content-Type: application/json" \
                    --header "Accept: application/json" -d "$k" https://"$DEST_DTR_URL"/enzi/v0/accounts/${i}/teams/${j}/members/${teamMemberName}?refresh_token="$DEST_DTR_TOKEN"
            done
        done
    done
}

## Needs to be finished
putTeamRepoAccess() {
    echo "putTeamRepoAccess"
}

########################### 
#        PUSH IMAGES      #
###########################
migrateImages() {
    echo "Image sync initiating"
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        set +e
        docker run -it -d --name dtr_migration_"$i" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /etc/docker:/etc/docker \
        -v ~/dtrsync:/dtrsync \
        -v ~/.docker/config.json:/.docker/config.json \
        --env-file conf.env \
        casaler/dtrctl -w "${i}"
        set -e
    done
}

migrateAccountImages() {
    # Push image as that DTR user
    docker login -u "${1}" -p "$SRC_DTR_PASSWORD" "$DEST_DTR_URL"

    echo "Migrating images for $1"
    cat ../dtrsync/$1/repoConfig | jq -c -r '.name' | while IFS= read -r j;
    do
        TAGS=$(curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
        https://"$SRC_DTR_URL"/api/v0/repositories/${1}/${j}/tags?refresh_token="$SRC_DTR_TOKEN" | \
        jq -c -r 'select(.tags != null) | .tags[].name')
        DEST_TAGS=$(curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
        https://"$DEST_DTR_URL"/api/v0/repositories/${1}/${j}/tags?pageSize="$SRC_NO_OF_REPOS" | \
        jq -c -r '.[] | "\(.name)=\(.updatedAt)"')

        for k in $TAGS;
        do
            echo "Pulling $SRC_DTR_URL/$1/$j:$k"
            docker pull "$SRC_DTR_URL/$1/$j:$k" > /dev/null

            SRC_IMAGE_DATE=$(docker inspect $SRC_DTR_URL/$1/$j:$k | jq -r '.[].Created')
            SRC_IMAGE_DATE=$(date --utc --date="$SRC_IMAGE_DATE" +"%Y-%m-%d %H:%M:%S")
                
            DEST_IMAGE_DATE=$(echo $DEST_TAGS | tr " " "\n" | grep "^$k=" | cut -f2 -d=)
            DEST_IMAGE_DATE=$(date --utc --date="$DEST_IMAGE_DATE" +"%Y-%m-%d %H:%M:%S")

            # Push only updated images, or images that do not exist
            if [[ $SRC_IMAGE_DATE > $DEST_IMAGE_DATE || ! $DEST_TAGS =~ (^|[[:space:]])"$k=" ]]
            then
                docker tag "$SRC_DTR_URL/$1/$j:$k" "$DEST_DTR_URL/$1/$j:$k"
                echo "Pushing $DEST_DTR_URL/$1/$j:$k"
                set +e
                docker push "$DEST_DTR_URL/$1/$j:$k" > /dev/null
                set -e
                # Check if the push succeeded
                if [ $? -eq 0 ]
                then
                    echo "INFO: Success"
                else
                    echo "ERROR: Pushing $DEST_DTR_URL/$1/$j:$k"
                    exit 1
                fi
                echo "Removing Destination image"
                if docker images | awk '{print $1":"$2}' | grep "$DEST_DTR_URL/$1/$j:$k" > /dev/null
                then
                    docker rmi "$DEST_DTR_URL/$1/$j:$k" > /dev/null
                fi
            else
                echo "INFO: Skipping $DEST_DTR_URL/$1/$j:$k"
            fi
            echo "Removing Source image"
            if docker images | awk '{print $1":"$2}' | grep "$SRC_DTR_URL/$1/$j:$k" > /dev/null
            then
                docker rmi "$SRC_DTR_URL/$1/$j:$k" > /dev/null
            fi
        done
        #Clean up images after each repo
        echo "Repo $j complete."
    done
    #Clean up images after each Org
    echo "Org $1 complete."
}

####################################################################
#                                                                  #
#  This relies on there being a teamConfig, so can ignore for now  #
#                                                                  #
####################################################################
printAccessMap() {
    echo "Printing Team and Repo Access"
    cat ../dtrsync/orgList | sort -u | while IFS= read -r i;
    do
        echo "$i"
        echo "-------------------------"
        cat ./$i/teamConfig | jq -r '.name' | while IFS= read -r j;
        do
            echo "  $j Members"
            cat ./$i/$j/members | while IFS= read -r member;
            do
                if [ $(echo $member | jq -r '.isAdmin') == 'true' ]
                then
                    access="Admin"
                else
                    access="Member"
                fi

                echo "     " $(echo $member | jq -r .name) "-"  "$access"
            done

            echo "  $j Repository Access"
            cat ./$i/$j/repoAccess | while IFS= read -r access;
            do
                repoName=$(echo $access | jq -r '.repository.name')
                accessLevel=$(echo $access | jq -r '.accessLevel')
                echo "     $i/$repoName - $accessLevel"
            done
            echo ""
        done
        echo ""
    done
}

####################################################################
#                                                                  #
# Check the repositories in the Source DTR to the Destination DTR  #
#                                                                  #
####################################################################
checkSpecificRepositories() {
    for e in "$@";
    do
        # Namespace and name of the repository
        repo1=$(echo $e | cut -f1 -d/ | sed 's/\"//')
        repo2=$(echo $e | cut -f2 -d/ | sed 's/\"//')

        SRC_TAGS=$(curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
            https://"$SRC_DTR_URL"/api/v0/repositories/$repo1/$repo2/tags?refresh_token="$SRC_DTR_TOKEN" | \
            jq -c -r '.tags[].name')
        DEST_TAGS=$(curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
            https://"$DEST_DTR_URL"/api/v0/repositories/$repo1/$repo2/tags?pageSize="$SRC_NO_OF_REPOS" | \
            jq -c -r '.[].name')
        
        for k in $SRC_TAGS;
        do
            # Skip images that have already been pushed to the Destination DTR
            if echo $DEST_TAGS | grep -w $k > /dev/null
            then
                continue
            else
                # Tag do not exist in the Destination DTR
                echo "INFO: $DEST_DTR_URL/$repo1/$repo2:$k does not exist"
            fi
        done
    done
}

checkRepositories() {
    echo "Checking difference..."
    SRC_REPOS=$(curl -u "$SRC_DTR_USER":"$SRC_DTR_PASSWORD" -s --insecure \
        https://"$SRC_DTR_URL"/api/v0/repositories?limit="$SRC_NO_OF_REPOS" | \
        jq '.repositories[] | {name: (.namespace + "/" + .name)} | .name')

    DEST_REPOS=$(curl -u "$DEST_DTR_USER":"$DEST_DTR_PASSWORD" -s --insecure \
        https://"$DEST_DTR_URL"/api/v0/repositories?pageSize="$SRC_NO_OF_REPOS" | \
        jq '.repositories[] | {name: (.namespace + "/" + .name)} | .name')

    EXISTING_REPOS=[]
    i=0
    for r in $SRC_REPOS;
    do
        if echo $DEST_REPOS | grep -w $r > /dev/null;
        then
            # Repository exists in Destintation DTR
            EXISTING_REPOS[$i]=$r
            i=$((i+1))
        else
            echo "INFO: $r is missing from $DEST_DTR_URL"
        fi
    done

    checkSpecificRepositories "${EXISTING_REPOS[@]}"
}

usage() {
    echo ""
    echo "Usage: dtrctl -c [confguration file] COMMAND"
    echo "Pronounced: dtr-control"
    echo ""
    echo "Options"
    echo ""
    echo "-s, --source-metadata  Pull org, repo, team, and team access metadata from source DTR and store locally"
    echo "-p, --push-metadata    Push org, repo, team, and team access metadata from local source to dest DTR"
    echo "-i, --image-sync       Pull images from source DTR and push to dest DTR"
    #echo "-a, --print-access     Print mapping of access rights between teams and repos"
    echo "-c, --compare          Compare images from the source DTR and the dest DTR"
    echo "-e, --everything       Run everything expect for compare"
    echo "-w, --worker [ARG]    Run migration for a specific user account"
    echo "--help                 Print usage"
    echo ""
}

## Parse arguments
if [[ $# -gt 0 ]]
then
    case "$1" in
        -p|--push-metadata)
        PUSH=1
        shift 1
        ;;

        -i|--image-sync)
        SYNC_IMAGES=1
        shift 1
        ;;

        -c|--compare)
        COMPARE=1
        shift 1
        ;;

        #-a|--print-access)
        #PRINT_ACCESS=1
        #shift 1
        #;;

        -s|--source-metadata)
        PULL=1
        shift 1
        ;;

        -e|--everything)
        ALL=1
        shift 1
        ;;

        -w|--worker)
        INVADER=1
        USER="$2"
        shift 1
        ;;

        -h|--help)
        usage
        exit 1
        ;;

        *)  
        echo "Unknown argument: $1"
        usage
        exit 1
        ;;

    esac
fi

#Entrypoint for program
main
