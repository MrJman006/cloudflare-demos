#! /usr/bin/env bash

THIS_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

THIS_SCRIPT_DIR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

PROJECT_DIR_PATH="$(cd "${THIS_SCRIPT_DIR_PATH}/.." && pwd -P)"

MANUAL_PAGE_TEMPLATE="$(cat <<'EOF'
    MANUAL_PAGE
        @{SCRIPT_NAME}

    USAGE
        @{SCRIPT_NAME} [options] <worker-source-dir>

    DESCRIPTION
        Remove a deployed cloudflare worker.

    OPTIONS
        -h|--help
            Show this manual page.

    ARGUMENTS
        <worker-source-dir>
            A cloudflare worker source directory. This can be the name of a
            worker source directory found in 'cloudflare/workers' or can be
            a path to a worker source directory.

    END
EOF
)"

SHOW_HELP="no"
WORKER_SOURCE_DIR=""
WORKER_SOURCE_DIR_PATH=""
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

    WORKER_SOURCE_DIR="${1}"
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

function checkWorkerSourceExists()
{
    #
    # Ensure the source directory exists.
    #

    if [ -e "${PROJECT_DIR_PATH}/cloudflare/workers/${WORKER_SOURCE_DIR}" ]
    then
        WORKER_SOURCE_DIR_PATH="${PROJECT_DIR_PATH}/cloudflare/workers/${WORKER_SOURCE_DIR}"
    elif [ -e "${WORKER_SOURCE_DIR}" ]
    then
        WORKER_SOURCE_DIR_PATH="${WORKER_SOURCE_DIR}"
    else
        echo "ERROR: Could not locate the worker source directory. Ensure the supplied worker directory exists and run the script again."
        return 1
    fi

    #
    # Ensure the source directory contains a 'wrangler.toml' config file.
    #

    WORKER_CONFIG_FILE_PATH="${WORKER_SOURCE_DIR_PATH}/wrangler.toml"

    if [ ! -e "${WORKER_CONFIG_FILE_PATH}" ]
    then
        echo "ERROR: The supplied worker source directory does not contain a 'wrangler.toml' config file. Ensure that a 'wrangler.toml' config file exists and run this script again."
        return 1
    fi

    return 0
}

function removeDeployedWorker()
{
    local WORKER_NAME="$(grep -P "^name = " "${WORKER_CONFIG_FILE_PATH}" | head -n 1 | tr -d " \"" | cut -d "=" -f 2)"

    echo ""
    echo "========"
    echo "Removing Deployed Worker: ${WORKER_NAME}"

    npx wrangler deployments list --config "${WORKER_CONFIG_FILE_PATH}" | grep -Pq "workers.api.error.service_not_found"
    RESULT=$?

    if [ ${RESULT} -ne 0 ]
    then
        echo "Removing worker."

        #
        # Using a no-op to start the pipe line to put wrangler in
        # non-interactive mode.
        #

        : | npx wrangler delete --config "${WORKER_CONFIG_FILE_PATH}" || return $?
    fi

    echo "Done."
    echo "========"
}

function main()
{
    if [ "${SHOW_HELP}" == "yes" ]
    then
        show_manual_page
        return 0
    fi

    checkNodePackageInstalled "esbuild" || return $?

    checkWorkerSourceExists || return $?

    removeDeployedWorker || return $?
}

parse_cli "$@" && main
