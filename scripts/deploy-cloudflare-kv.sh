#! /usr/bin/env bash

THIS_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

THIS_SCRIPT_DIR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

PROJECT_DIR_PATH="$(cd "${THIS_SCRIPT_DIR_PATH}/.." && pwd -P)"

MANUAL_PAGE_TEMPLATE="$(cat <<'EOF'
    MANUAL_PAGE
        @{SCRIPT_NAME}

    USAGE
        @{SCRIPT_NAME} [optons] <kv-config>

    DESCRIPTION
        Deploy a cloudflare KV.

    OPTIONS
        -h|--help
            Show this manual page.

    ARGUMENTS
        <kv-config>
            A cloudflare KV config. This can be the name of a config file found
            in 'cloudflare/kvs' or can be a path to a config file.

    END
EOF
)"

SHOW_HELP="no"
KV_CONFIG=""
KV_CONFIG_FILE_PATH=""

function show_manual_page()
{
    #
    # Instantiate the template.
    #

    local TEMP_FILE="$(mktemp --tmpdir="/dev/shm" "XXXXXX-help.txt")"

    echo "${MANUAL_PAGE_TEMPLATE}" > "${TEMP_FILE}"

    #
    # Remove leading spaces and fill in template fields.
    #

    sed -ri "s/^\s{4}//" "${TEMP_FILE}"

    sed -ri "s/@\{SCRIPT_NAME\}/${THIS_SCRIPT_NAME}/g" "${TEMP_FILE}"

    #
    # Print to console.
    #

    cat "${TEMP_FILE}"

    #
    # Clean up.
    #

    rm "${TEMP_FILE}"
}

function parse_cli()
{
    #
    # Parse options.
    #

    while [ 1 ]
    do
        case "${1}" in
            -h|--help)
                shift
                SHOW_HELP="yes"
                return 0
                ;;
            *)
                if [ "${1:0:1}" == "-" ] && [ "${1}" != "--" ]
                then
                    echo "Invalid option '${1}'. Need --help?"
                    return 1
                fi

                if [ "${1}" == "--" ]
                then
                    shift
                fi

                break
                ;;
        esac
    done

    #
    # Parse arugments.
    #

    if [ $# -lt 1 ]
    then
        echo "Missing required arguments. Need --help?"
        return 1
    fi

    KV_CONFIG="${1}"
}

function checkKvConfigFileExists()
{
    #
    # Ensure the KV config file exists.
    #

    if [ -e "${PROJECT_DIR_PATH}/cloudflare/kvs/${KV_CONFIG}.toml" ]
    then
        KV_CONFIG_FILE_PATH="${PROJECT_DIR_PATH}/cloudflare/kvs/${KV_CONFIG}.toml"
    elif [ -e "${KV_CONFIG}" ]
    then
        KV_CONFIG_FILE_PATH="${KV_CONFIG}"
    else
        echo "ERROR: Could not locate the KV config file. Ensure the config file exists and run the script again."
        return 1
    fi

    return 0
}

function checkNodePackageInstalled()
{
    local PACKAGE_NAME="${1}"

    if [ ! -e "${PROJECT_DIR_PATH}/node_modules/${PACKAGE_NAME}" ]
    then
        echo "ERROR: Could not locate the node package '${PACKAGE_NAME}'. Please install it and run this script again."
        return 1
    fi

    return 0
}

function deployKv()
{
    local KV_NAME="$(grep -P "^name = " "${KV_CONFIG_FILE_PATH}" | head -n 1 | tr -d " \"" | cut -d "=" -f 2)"

    echo ""
    echo "========"
    echo "Deploying KV: ${KV_NAME}"

    #
    # Create a dummy worker to satisfy the KV deployment process.
    #

    local TEMP_FILE="$(mktemp --tmpdir=/dev/shm XXXXXX-wrangler.toml)"
  
    echo "name = \"kv\"" > "${TEMP_FILE}"

    #
    # Deploy the KV if it has not already been deployed.
    #

    local DEPLOYED_KV_NAMESPACES="$(npx wrangler kv:namespace list)"

    echo "${DEPLOYED_KV_NAMESPACES}" | grep -Pq "${KV_NAME}"
    RESULT=$?

    if [ ${RESULT} -ne 0 ]
    then
        npx wrangler kv:namespace create --config "${TEMP_FILE}" "${KV_NAME}" || return $?
        DEPLOYED_KV_NAMESPACES="$(npx wrangler kv:namespace list)"
    fi

    #
    # Fill the KV with configured data. Each key value pair are assumed to be
    # on a single line. Multi-line strings are not currently supported.
    #

    local DEPLOYED_KV_INDEX=$(echo "${DEPLOYED_KV_NAMESPACES}" | grep "\"title\":" | grep -n "\"title\":" | tr -d " ,\"" | cut -d ":" -f 1,3 | grep "${KV_NAME}" | cut -d ":" -f 1)
    local DEPLOYED_KV_ID="$(echo "${DEPLOYED_KV_NAMESPACES}" | grep "\"id\":" | grep -n "\"id\":" | tr -d " ,\"" | cut -d ":" -f 1,3 | grep -P "^${DEPLOYED_KV_INDEX}" | cut -d ":" -f 2)"

    local ADDING_DATA="no"
    while read LINE
    do
        #
        # Skip blank and comment lines.
        #

        echo "${LINE}" | grep -Pq "^($|#)"
        RESULT=$?

        if [ ${RESULT} -eq 0 ]
        then
            continue
        fi

        #
        # Lines following 'data' sections should be processed as key value
        # pairs for the KV.
        #

        echo "${LINE}" | grep -Pq "^\s*\[data\]\s*$"
        RESULT=$?

        if [ ${RESULT} -eq 0 ]
        then
            ADDING_DATA="yes"
            continue
        fi

        #
        # Other sections should not be processed for key value pairs.
        #

        echo "${LINE}" | grep -Pq "^\s*\[[a-zA-Z0-9-_]+\]\s*$"
        RESULT=$?

        if [ ${RESULT} -eq 0 ]
        then
            ADDING_DATA="no"
            continue
        fi

        #
        # Add the key value pair to the KV.
        #

        if [ "${ADDING_DATA}" == "no" ]
        then
            continue
        fi

        local KEY="$(echo "${LINE}" | cut -d "=" -f 1 | sed -r -e "s/ $//")"
        local VALUE="$(echo "${LINE}" | cut -d "=" -f 2 | sed -r -e "s/^ //" -e "s/(^\"|\"$)//g")"

        echo "Adding key '${KEY}' to the KV."
        npx wrangler kv:key put --namespace-id="${DEPLOYED_KV_ID}" "${KEY}" "${VALUE}" 1>/dev/null
    done < <(cat "${KV_CONFIG_FILE_PATH}")

    echo "========"
}

function main()
{
    if [ "${SHOW_HELP}" == "yes" ]
    then
        show_manual_page
        return 0
    fi

    checkNodePackageInstalled "wrangler" || return $?

    checkKvConfigFileExists || return $?

    deployKv || return $?
}

parse_cli "$@" && main
