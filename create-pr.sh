#!/bin/bash

set -e

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Create an Azure DevOps pull request from the current branch"
    echo ""
    echo "Options:"
    echo "  -t, --title TITLE              PR title (required)"
    echo "  -d, --description DESC         PR description"
    echo "  -s, --source-branch BRANCH     Source branch (defaults to current branch)"
    echo "  -T, --target-branch BRANCH     Target branch (defaults to 'main')"
    echo "  -r, --reviewers USERS          Space-separated list of reviewers"
    echo "  -R, --required-reviewers USERS Space-separated list of required reviewers"
    echo "  -w, --work-items IDS           Space-separated list of work item IDs"
    echo "  --draft                        Create as draft PR"
    echo "  --auto-complete                Enable auto-complete when conditions are met"
    echo "  --delete-source-branch         Delete source branch after merge"
    echo "  --transition-work-items        Transition linked work items to next state"
    echo "  --open                         Open PR in browser after creation"
    echo "  --repository REPO              Repository name or ID"
    echo "  --organization ORG             Azure DevOps organization"
    echo "  --project PROJECT              Project name"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  AZURE_DEVOPS_EXT_PAT          Personal Access Token for authentication"
    echo ""
    echo "Examples:"
    echo "  $0 --title \"Add new feature\" --description \"This adds feature X\""
    echo "  $0 -t \"Bug fix\" -d \"Fixes issue #123\" --reviewers \"user1@company.com user2@company.com\""
    echo "  $0 -t \"Feature\" --draft --auto-complete --delete-source-branch"
}

TITLE=""
DESCRIPTION=""
SOURCE_BRANCH=""
TARGET_BRANCH="main"
REVIEWERS=""
REQUIRED_REVIEWERS=""
WORK_ITEMS=""
DRAFT=false
AUTO_COMPLETE=false
DELETE_SOURCE_BRANCH=false
TRANSITION_WORK_ITEMS=false
OPEN_BROWSER=false
REPOSITORY=""
ORGANIZATION=""
PROJECT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--title)
            TITLE="$2"
            shift 2
            ;;
        -d|--description)
            DESCRIPTION="$2"
            shift 2
            ;;
        -s|--source-branch)
            SOURCE_BRANCH="$2"
            shift 2
            ;;
        -T|--target-branch)
            TARGET_BRANCH="$2"
            shift 2
            ;;
        -r|--reviewers)
            REVIEWERS="$2"
            shift 2
            ;;
        -R|--required-reviewers)
            REQUIRED_REVIEWERS="$2"
            shift 2
            ;;
        -w|--work-items)
            WORK_ITEMS="$2"
            shift 2
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --auto-complete)
            AUTO_COMPLETE=true
            shift
            ;;
        --delete-source-branch)
            DELETE_SOURCE_BRANCH=true
            shift
            ;;
        --transition-work-items)
            TRANSITION_WORK_ITEMS=true
            shift
            ;;
        --open)
            OPEN_BROWSER=true
            shift
            ;;
        --repository)
            REPOSITORY="$2"
            shift 2
            ;;
        --organization)
            ORGANIZATION="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$TITLE" ]; then
    echo "Error: Title is required. Use -t or --title to specify it."
    echo ""
    usage
    exit 1
fi

if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it first."
    echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

if ! az extension show --name azure-devops &> /dev/null; then
    echo "Azure DevOps extension not found. Installing..."
    az extension add --name azure-devops
fi

if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "Error: Not in a git repository"
    exit 1
fi

if [ -z "$SOURCE_BRANCH" ]; then
    SOURCE_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    if [ -z "$SOURCE_BRANCH" ]; then
        echo "Error: Could not determine current branch. Please specify with -s or --source-branch"
        exit 1
    fi
    echo "Using current branch as source: $SOURCE_BRANCH"
fi

if ! git rev-parse --verify "$SOURCE_BRANCH" &> /dev/null; then
    echo "Error: Source branch '$SOURCE_BRANCH' does not exist"
    exit 1
fi

if [ "$SOURCE_BRANCH" = "$TARGET_BRANCH" ]; then
    echo "Error: Source and target branches cannot be the same"
    exit 1
fi

echo "Creating pull request..."
echo "  Title: $TITLE"
echo "  Source: $SOURCE_BRANCH"
echo "  Target: $TARGET_BRANCH"
[ -n "$DESCRIPTION" ] && echo "  Description: $DESCRIPTION"
[ -n "$REVIEWERS" ] && echo "  Reviewers: $REVIEWERS"
[ -n "$REQUIRED_REVIEWERS" ] && echo "  Required reviewers: $REQUIRED_REVIEWERS"
[ -n "$WORK_ITEMS" ] && echo "  Work items: $WORK_ITEMS"
[ "$DRAFT" = true ] && echo "  Draft: Yes"
[ "$AUTO_COMPLETE" = true ] && echo "  Auto-complete: Yes"
[ "$DELETE_SOURCE_BRANCH" = true ] && echo "  Delete source branch: Yes"

PR_CMD="az repos pr create --title \"$TITLE\" --source-branch \"$SOURCE_BRANCH\" --target-branch \"$TARGET_BRANCH\""

[ -n "$DESCRIPTION" ] && PR_CMD="$PR_CMD --description \"$DESCRIPTION\""
[ -n "$REVIEWERS" ] && PR_CMD="$PR_CMD --reviewers $REVIEWERS"
[ -n "$REQUIRED_REVIEWERS" ] && PR_CMD="$PR_CMD --required-reviewers $REQUIRED_REVIEWERS"
[ -n "$WORK_ITEMS" ] && PR_CMD="$PR_CMD --work-items $WORK_ITEMS"
[ -n "$REPOSITORY" ] && PR_CMD="$PR_CMD --repository \"$REPOSITORY\""
[ -n "$ORGANIZATION" ] && PR_CMD="$PR_CMD --organization \"$ORGANIZATION\""
[ -n "$PROJECT" ] && PR_CMD="$PR_CMD --project \"$PROJECT\""
[ "$DRAFT" = true ] && PR_CMD="$PR_CMD --draft"
[ "$AUTO_COMPLETE" = true ] && PR_CMD="$PR_CMD --auto-complete"
[ "$DELETE_SOURCE_BRANCH" = true ] && PR_CMD="$PR_CMD --delete-source-branch"
[ "$TRANSITION_WORK_ITEMS" = true ] && PR_CMD="$PR_CMD --transition-work-items"
[ "$OPEN_BROWSER" = true ] && PR_CMD="$PR_CMD --open"

echo ""
echo "Executing: $PR_CMD"
echo ""

if ! eval $PR_CMD; then
    echo ""
    echo "Error: Failed to create pull request"
    echo ""
    echo "Possible issues:"
    echo "  - Not authenticated with Azure DevOps (set AZURE_DEVOPS_EXT_PAT or run 'az devops login')"
    echo "  - Invalid organization, project, or repository settings"
    echo "  - Source branch not pushed to remote"
    echo "  - Insufficient permissions"
    echo "  - PR with same source/target already exists"
    echo ""
    echo "Try running 'az devops configure --list' to check your current configuration"
    exit 1
fi

echo ""
echo "Pull request created successfully!"