#! /usr/bin/env bash

THIS_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

THIS_SCRIPT_DIR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

PROJECT_DIR_PATH="$(cd "${THIS_SCRIPT_DIR_PATH}/.." && pwd -P)"

MANUAL_PAGE_TEMPLATE="$(cat <<'EOF'
    MANUAL_PAGE
        @{SCRIPT_NAME}

    USAGE
        @{SCRIPT_NAME}

    DESCRIPTION
        Deploy all cloudflare workers.

    END
EOF
)"

fn_print_manual_page()
{
    #
    # Instantiate the template.
    #

    local TEMP_FILE="$(mktemp --tmpdir="/dev/shm")"

    echo "${MANUAL_PAGE_TEMPLATE}" > "${TEMP_FILE}"

    # Remove leading spaces.
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

fn_parse_cli()
{
    echo "$@" | grep -Pq "(^|\s+)(-h|--help)(\s+|$)"
    RESULT=$?

    if [ ${RESULT} -eq 0 ]
    then
        fn_print_manual_page
        return 1
    fi
}

function checkWorkerBuildsExist()
{
    if [ ! -e "${PROJECT_DIR_PATH}/_cloudflare" ]
    then
        echo "Could not find any cloudflare worker builds. Please build the cloudflare workers and run this script again."
        return 1
    fi

    return 0
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

function deployWorkers()
{
    local WORKER_CONFIG_LIST=($(find "${PROJECT_DIR_PATH}/_cloudflare" -name wrangler.toml -print))

    for WORKER_CONFIG in "${WORKER_CONFIG_LIST[@]}"
    do
        local WORKER_DIR_PATH="$(dirname "${WORKER_CONFIG}")"
        local WORKER_NAME="$(basename "${WORKER_DIR_PATH}")"

        local CMD=("${THIS_SCRIPT_DIR_PATH}/deploy-cloudflare-worker.sh" "${WORKER_NAME}")
        "${CMD[@]}"
    done
}

fn_main()
{
    checkWorkerBuildsExist || return $?

    checkNodePackageInstalled "wrangler" || return $?

    deployWorkers || return $?
}

fn_parse_cli "$@" && fn_main
