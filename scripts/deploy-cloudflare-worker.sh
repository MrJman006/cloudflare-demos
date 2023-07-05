#! /usr/bin/env bash

THIS_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

THIS_SCRIPT_DIR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

PROJECT_DIR_PATH="$(cd "${THIS_SCRIPT_DIR_PATH}/.." && pwd -P)"

MANUAL_PAGE_TEMPLATE="$(cat <<'EOF'
    MANUAL_PAGE
        @{SCRIPT_NAME}

    USAGE
        @{SCRIPT_NAME} [optons] <worker-build-dir>

    DESCRIPTION
        Deploy a built cloudflare worker.

    OPTIONS
        -h|--help
            Show this manual page.

    ARGUMENTS
        <worker-build-dir>
            A cloudflare worker build directory. This can be the name of a
            build directory found in '_cloudflare/workers' or can be a path
            to a worker build directory.

    END
EOF
)"

SHOW_HELP=""
WORKER_BUILD_DIR=""
WORKER_BUILD_DIR=""
WORKER_CONFIG_FILE_PATH=""

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

    WORKER_BUILD_DIR="${1}"
}

function checkNodePackageInstalled()
{
    local PACKAGE_NAME="${1}"

    if [ ! -e "${PROJECT_DIR_PATH}/node_modules/${PACKAGE_NAME}" ]
    then
        echo "Could not locate the node package '${PACKAGE_NAME}'. Please install it and run this script again."
        return 1
    fi

    return 0
}

function checkWorkerBuildExists()
{
    #
    # Ensure the worker build directory exists.
    #

    if [ -e "${PROJECT_DIR_PATH}/_cloudflare/workers/${WORKER_BUILD_DIR}" ]
    then
        WORKER_BUILD_DIR_PATH="${PROJECT_DIR_PATH}/_cloudflare/workers/${WORKER_BUILD_DIR}"
    elif [ -e "${WORKER_BUILD_DIR}" ]
    then
        WORKER_BUILD_DIR_PATH="${WORKER_BUILD_DIR}"
    else
        echo "ERROR: Could not locate the worker build directory. Ensure the supplied worker directory exists and run the script again."
        return 1
    fi

    #
    # Ensure the build directory contains a 'wrangler.toml' config file.
    #

    WORKER_CONFIG_FILE_PATH="${WORKER_BUILD_DIR_PATH}/wrangler.toml"

    if [ ! -e "${WORKER_CONFIG_FILE_PATH}" ]
    then
        echo "ERROR: The supplied worker build directory does not contain a 'wrangler.toml' config file. Ensure that a 'wrangler.toml' config file exists and run this script again."
        return 1
    fi

    return 0
}

function fillInWorkerKvs()
{
    #
    # Check if the current worker has any automation data for KV Namespaces.
    #

    grep -Pq "^# Automation Meta-Data: KV Namespaces" "${WORKER_CONFIG_FILE_PATH}"
    RESULT=$?

    if [ ${RESULT} -ne 0 ]
    then
        return 0
    fi

    echo "Found KV automation meta-data."

    #
    # Collect automation meta-data for KV Namespaces.
    #

    local KV_NAME_LIST=($(cat "${WORKER_CONFIG_FILE_PATH}" | grep "KV Name:" | tr -d " " | cut -d ":" -f 2 ))
    local KV_BINDING_LIST=($(cat "${WORKER_CONFIG_FILE_PATH}" | grep "KV Binding:" | tr -d " " | cut -d ":" -f 2 ))

    #
    # For each KV defined in the automation meta-data, add it to the worker
    # config file if it does not already exist.
    #

    local DEPLOYED_KV_NAMESPACES="$(npx wrangler kv:namespace list)"

    local I
    for I in ${!KV_NAME_LIST[@]}
    do
        local KV_NAME="${KV_NAME_LIST[${I}]}"
        local KV_BINDING="${KV_BINDING_LIST[${I}]}"

        #
        # Check if the KV has been deployed.
        #

        echo "${DEPLOYED_KV_NAMESPACES}" | grep -q "${KV_NAME}"
        RESULT=$?

        if [ ${RESULT} -ne 0 ]
        then
            echo "Could not locate a deployed KV Namespace with name '${KV_NAME}'. Deploy a KV Namespace with the name '${KV_NAME}' and run this script again."
            return 1
        fi

        #
        # Check if the KV needs to be added to the worker config.
        #

        grep -q "name = \"${KV_NAME}\"" "${WORKER_CONFIG_FILE_PATH}"
        RESULT=$?

        if [ ${RESULT} -ne 0 ]
        then
            local DEPLOYED_KV_INDEX=$(echo "${DEPLOYED_KV_NAMESPACES}" | grep "\"title\":" | grep -n "\"title\":" | tr -d " ,\"" | cut -d ":" -f 1,3 | grep "${KV_NAME}" | cut -d ":" -f 1)
            local DEPLOYED_KV_ID="$(echo "${DEPLOYED_KV_NAMESPACES}" | grep "\"id\":" | grep -n "\"id\":" | tr -d " ,\"" | cut -d ":" -f 1,3 | grep -P "^${DEPLOYED_KV_INDEX}" | cut -d ":" -f 2)"

            echo "Adding KV Namespace '${KV_NAME}' to the config."

            echo "" >> "${WORKER_CONFIG_FILE_PATH}"
            echo "[[kv_namespaces]]" >> "${WORKER_CONFIG_FILE_PATH}"
            echo "name = \"${KV_NAME}\"" >> "${WORKER_CONFIG_FILE_PATH}"
            echo "binding = \"${KV_BINDING}\"" >> "${WORKER_CONFIG_FILE_PATH}"
            echo "id = \"${DEPLOYED_KV_ID}\"" >> "${WORKER_CONFIG_FILE_PATH}"
        fi
    done
}

function deployWorkerSecrets()
{
    #
    # Check if the current worker has any automation meta-data for Secret Variables.
    #

    grep -Pq "^# Automation Meta-Data: Secret Variables" "${WORKER_CONFIG_FILE_PATH}"
    RESULT=$?

    if [ ${RESULT} -ne 0 ]
    then
        return 0
    fi

    echo "Found Secret Variables automation meta-data."

    #
    # Ensure a secret variables config file exists in the worker build
    # directory.
    #

    local SECRET_VARS_JSON_PATH="${WORKER_BUILD_DIR_PATH}/secret-variables.json"

    if [ ! -e "${SECRET_VARS_JSON_PATH}" ]
    then
        echo "ERROR: This worker relies on secret variables and no secret variable config file was found in the build directory. You must create a secret variables config file in the build directory of the worker and re-run this script. The config file must be named 'secret-variables.json' and contain a json object that maps a single key value pair for each required secret variable. See the worker's 'wrangler.toml' for a list of required secret variables."
        return 1
    fi

    npx wrangler secret:bulk --compatibility-date "$(date +%Y-%m-%d)" --config "${WORKER_CONFIG_FILE_PATH}" "${SECRET_VARS_JSON_PATH}"
}

function deployWorker()
{
    local WORKER_NAME="$(grep -P "^name = " "${WORKER_CONFIG_FILE_PATH}" | head -n 1 | tr -d " \"" | cut -d "=" -f 2)"

    echo ""
    echo "========"
    echo "Deploying Worker: ${WORKER_NAME}"

    fillInWorkerKvs || return $?

    npx wrangler deploy --compatibility-date "$(date +%Y-%m-%d)" --config "${WORKER_CONFIG_FILE_PATH}" || return $?

    deployWorkerSecrets || return $?

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

    checkWorkerBuildExists || return $?

    deployWorker || return $?
}

parse_cli "$@" && main
