#!/usr/bin/env bash
set -e

ORG="${ORG:-}"
DONOR="${DONOR:-}"
MODULE="${MODULE:-}"
REPO="${REPO:-}"
BRANCH="${BRANCH:-main}"
WORKDIR="${WORKDIR:-/tmp/terraform-extract}"
DRY_RUN="${DRY_RUN:-0}"
HELP_FLAG="${HELP_FLAG:-0}"
VALID_ARGUMENTS=0

usage() {
    echo "Usage: $0 [-n] [-o ORG] [-d DONOR] [-m MODULE] [-r REPO] [-w WORKDIR] [-h]"
    echo ""
    echo "Options:"
    echo "  -n  Perform a dry run of the extraction process without pushing changes to the target repository"
    echo "  -o  The GitHub organization to clone the donor repository from"
    echo "  -d  The name of the donor repository"
    echo "  -m  The name of the module to extract, relative to the root of the donor repository eg: github dir/module"
    echo "  -r  The name of the recipient repository to add the module to"
    echo "  -w  The working directory to use for extracting the module"
    echo "  -h  Display this help message"
    exit 2
}

# Parse command line options
while getopts "no:d:m:r:w:h" opt; do
    case ${opt} in
        n) DRY_RUN=1 ;;
        o) ORG="${OPTARG}" ;;
        d) DONOR="${OPTARG}" ;;
        m) MODULE="${OPTARG}" ;;
        r) REPO="${OPTARG}" ;;
        w) WORKDIR="${OPTARG}" ;;
        h) HELP_FLAG=1; usage ;;
        \?) echo "Invalid option: -${OPTARG}" >&2; usage ;;
        :) echo "Option -${OPTARG} requires an argument." >&2; usage ;;
    esac
done
shift $((OPTIND -1))

# If not all required arguments are provided, display the usage message and exit
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
fi

function validate_opts() {
    if [[ -z "$ORG" || -z "$DONOR" || -z "$MODULE" || -z "$REPO" ]]; then
        echo "Error: All options must be provided."
        echo "Please provide the organization, donor, module, and repository."
        usage
        exit 1
    fi
}

function prepare_workdir() {
    mkdir -p $WORKDIR || exit 1
}

function prepare_donor() {
    # Clone the donor repository and prepare the module
    cd $WORKDIR || exit 1
    echo "Cloning donor repository: ${ORG}/${DONOR}"
    echo "this would be the clone"
    git clone --no-tags --single-branch --branch=main https://github.com/$ORG/$DONOR.git
    cd $DONOR || exit 1
    echo "Extracting module: $MODULE"
    # Check if CHANGELOG.md exists and rename it to OLD_CHANGELOG.md
    if [ -f "CHANGELOG.md" ]; then
        echo "Renaming CHANGELOG.md to OLD_CHANGELOG.md"
        mv CHANGELOG.md OLD_CHANGELOG.md
        git commit -a -m "Rename CHANGELOG.md to OLD_CHANGELOG.md"
    fi
    git subtree split -P $MODULE -b split/$MODULE
    # Fix up the history so it conforms to conventional commit standards
    echo "Fixing up commit messages"
    git filter-branch -f --msg-filter 'sed "s/^/refactor: /g"' split/$MODULE
    cd $WORKDIR || exit 1
}

function prepare_recipient() {
    # Clone the recipient repository and add the donor repository as a remote
    cd $WORKDIR || exit 1
    echo "Cloning target repository: $ORG/$REPO"
    git clone https://github.com/$ORG/$REPO.git
    cd $REPO || exit 1
    echo "Adding donor repository as remote"
    git remote add donor $WORKDIR/$DONOR
    echo "Fetching module from donor repository"
    git pull --rebase -X theirs donor split/$MODULE
    cd $WORKDIR || exit 1
}

function push_new_module() {
    echo "Pushing changes to target repository"
    cd $WORKDIR/$REPO || exit 1
    git push --force --set-upstream origin $BRANCH
    cd $WORKDIR || exit 1
}

if [[ $HELP_FLAG -eq 1 ]]; then
    usage
  else
      echo "Running module splitter"
      validate_opts
      prepare_workdir
      prepare_donor
      prepare_recipient
    if [[ $DRY_RUN -eq 0 ]]; then
      echo "Pushing changes to target repository"
      push_new_module
    fi
fi
