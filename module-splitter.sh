#!/usr/bin/env bash

ORG="${ORG:-}"
DONOR="${DONOR:-}"
MODULE="${MODULE:-}"
REPO="${REPO:-}"
WORKDIR="${WORKDIR:-/tmp/terraform-extract}"
DRY_RUN="${DRY_RUN:-0}"

# A function to display a usage message
usage() {
    echo "Usage: $0 [-n| --dry-run] [-o|--org ORG] [-d|--donor DONOR] [-m|--module MODULE] [-r|--repo REPO] [-w|--workdir WORKDIR] [-h|--help]"
    echo ""
    echo "Options:"
    echo "  -n, --dry-run  Perform a dry run of the extraction process without pushing changes to the target repository"
    echo "  -o, --org    The GitHub organization to clone the donor repository from"
    echo "  -d, --donor  The name of the donor repository"
    echo "  -m, --module The name of the module to extract, relative to the root of the donor repository eg: github dir/module"
    echo "  -r, --repo   The name of the recipient repository to add the module to"
    echo "  -w, --workdir The working directory to use for extracting the module"
    echo "  -h, --help   Display this help message"
    exit 2
}

# Parse command line options
PARSED_ARGUMENTS=$(getopt -n "$0" -o o:d:m:r:w:h --long org:,donor:,module:,repo:,workdir:,help -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
fi

eval set -- "$PARSED_ARGUMENTS"
while :
do
    case "$1" in
        -n | --dry-run) DRY_RUN=1 ; shift ;;
        -o | --org) ORG="$2" ; shift 2 ;;
        -d | --donor) DONOR="$2" ; shift 2 ;;
        -m | --module) MODULE="$2" ; shift 2 ;;
        -r | --repo) REPO="$2" ; shift 2 ;;
        -w | --workdir) WORKDIR="$2" ; shift 2 ;;
        -h | --help) HELP_FLAG=1; usage ;;
        --) shift; break ;;
        *) echo "Unexpected option: $1 - this should not happen."
           usage ;;
    esac
done

function validate_opts() {
    if [[ -z "$ORG" || -z "$DONOR" || -z "$MODULE" || -z "$REPO" ]]; then
        echo "Error: All options must be provided."
        echo "Please provide the organization, donor, module, and repository."
        usage
        exit 1
    fi
}

function prepare_workdir() {
    mkdir $WORKDIR || exit 1
}

function prepare_donor() {
    # Clone the donor repository and prepare the module
    echo "Cloning donor repository: ${ORG}/${DONOR}"
    echo "this would be the clone"
    git clone --no-tags --single-branch --branch=main git@github.com:$ORG/$DONOR.git
    pushd $DONOR || exit 1
    echo "Extracting module: $MODULE"
    git subtree split -P $MODULE -b split/$MODULE
    # Fix up the history so it conforms to conventional commit standards
    echo "Fixing up commit messages"
    git filter-branch -f --msg-filter 'sed "s/^/refactor: /g"' split/$MODULE
    popd || exit 1
}

function prepare_recipient() {
    # Clone the recipient repository and add the donor repository as a remote
    pushd $WORKDIR || exit 1
    echo "Cloning target repository: $ORG/$REPO"
    git clone git@github.com:$ORG/$REPO.git
    pushd "$REPO" || exit 1
    echo "Adding donor repository as remote"
    git remote add donor $WORKDIR/$DONOR
    echo "Fetching module from donor repository"
    git pull --rebase -X thiers donor split/$MODULE
    popd
}

function push_new_module() {
    echo "Pushing changes to target repository"
    pushd $WORKDIR || exit 1
    git push --force --set-upstream origin main
    popd || exit 1
}

if [ "$HELP_FLAG" -eq 1 ]; then
    validate_opts
    prepare_workdir
    prepare_donor
    prepare_recipient
    if [ "$DRY_RUN" -eq 0 ]; then
        push_new_module
    fi
fi
