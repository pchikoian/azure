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

if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install it first."
    exit 1
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

if [ -z "$AZURE_DEVOPS_EXT_PAT" ]; then
    echo "Error: AZURE_DEVOPS_EXT_PAT environment variable is required for authentication"
    exit 1
fi

if [ -z "$ORGANIZATION" ]; then
    echo "Error: Organization is required. Use --organization to specify it."
    exit 1
fi

if [ -z "$PROJECT" ]; then
    echo "Error: Project is required. Use --project to specify it."
    exit 1
fi

if [ -z "$REPOSITORY" ]; then
    REPOSITORY=$(basename $(git remote get-url origin 2>/dev/null) .git 2>/dev/null || echo "")
    if [ -z "$REPOSITORY" ]; then
        echo "Error: Could not determine repository name. Please specify with --repository"
        exit 1
    fi
    echo "Using repository: $REPOSITORY"
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

REVIEWERS_JSON="[]"
if [ -n "$REVIEWERS" ]; then
    REVIEWERS_JSON="[]"
    for reviewer in $REVIEWERS; do
        if [ "$REVIEWERS_JSON" = "[]" ]; then
            REVIEWERS_JSON="[{\"id\":\"$reviewer\"}]"
        else
            REVIEWERS_JSON="${REVIEWERS_JSON%]}},{\"id\":\"$reviewer\"}]"
        fi
    done
fi

REQUIRED_REVIEWERS_JSON="[]"
if [ -n "$REQUIRED_REVIEWERS" ]; then
    REQUIRED_REVIEWERS_JSON="[]"
    for reviewer in $REQUIRED_REVIEWERS; do
        if [ "$REQUIRED_REVIEWERS_JSON" = "[]" ]; then
            REQUIRED_REVIEWERS_JSON="[{\"id\":\"$reviewer\",\"isRequired\":true}]"
        else
            REQUIRED_REVIEWERS_JSON="${REQUIRED_REVIEWERS_JSON%]}},{\"id\":\"$reviewer\",\"isRequired\":true}]"
        fi
    done
fi

WORK_ITEMS_JSON="[]"
if [ -n "$WORK_ITEMS" ]; then
    WORK_ITEMS_JSON="[]"
    for item in $WORK_ITEMS; do
        if [ "$WORK_ITEMS_JSON" = "[]" ]; then
            WORK_ITEMS_JSON="[{\"id\":\"$item\"}]"
        else
            WORK_ITEMS_JSON="${WORK_ITEMS_JSON%]}},{\"id\":\"$item\"}]"
        fi
    done
fi

JSON_PAYLOAD="{"
JSON_PAYLOAD="$JSON_PAYLOAD\"sourceRefName\":\"refs/heads/$SOURCE_BRANCH\","
JSON_PAYLOAD="$JSON_PAYLOAD\"targetRefName\":\"refs/heads/$TARGET_BRANCH\","
JSON_PAYLOAD="$JSON_PAYLOAD\"title\":\"$TITLE\""
[ -n "$DESCRIPTION" ] && JSON_PAYLOAD="$JSON_PAYLOAD,\"description\":\"$DESCRIPTION\""
[ "$DRAFT" = true ] && JSON_PAYLOAD="$JSON_PAYLOAD,\"isDraft\":true"
[ "$REVIEWERS_JSON" != "[]" ] && JSON_PAYLOAD="$JSON_PAYLOAD,\"reviewers\":$REVIEWERS_JSON"
[ "$REQUIRED_REVIEWERS_JSON" != "[]" ] && JSON_PAYLOAD="$JSON_PAYLOAD,\"reviewers\":$REQUIRED_REVIEWERS_JSON"
[ "$WORK_ITEMS_JSON" != "[]" ] && JSON_PAYLOAD="$JSON_PAYLOAD,\"workItemRefs\":$WORK_ITEMS_JSON"
JSON_PAYLOAD="$JSON_PAYLOAD}"

API_URL="https://dev.azure.com/$ORGANIZATION/$PROJECT/_apis/git/repositories/$REPOSITORY/pullrequests?api-version=7.1"

echo ""
echo "Making API call to: $API_URL"
echo "Payload: $JSON_PAYLOAD"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Basic $(echo -n ":$AZURE_DEVOPS_EXT_PAT" | base64 -w 0)" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    "$API_URL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -eq 201 ]; then
    echo "Pull request created successfully!"
    
    PR_ID=$(echo "$RESPONSE_BODY" | grep -o '"pullRequestId":[0-9]*' | cut -d':' -f2)
    PR_URL=$(echo "$RESPONSE_BODY" | grep -o '"_links":{[^}]*"web":{[^}]*"href":"[^"]*' | sed 's/.*"href":"//')
    
    if [ -n "$PR_ID" ]; then
        echo "PR ID: $PR_ID"
    fi
    if [ -n "$PR_URL" ]; then
        echo "PR URL: $PR_URL"
        
        if [ "$OPEN_BROWSER" = true ]; then
            if command -v xdg-open &> /dev/null; then
                xdg-open "$PR_URL"
            elif command -v open &> /dev/null; then
                open "$PR_URL"
            else
                echo "Cannot open browser automatically. Please visit the URL above."
            fi
        fi
    fi
    
    if [ "$AUTO_COMPLETE" = true ] && [ -n "$PR_ID" ]; then
        echo "Setting up auto-complete..."
        AUTO_COMPLETE_PAYLOAD="{\"autoCompleteSetBy\":{\"id\":\"me\"}}"
        if [ "$DELETE_SOURCE_BRANCH" = true ]; then
            AUTO_COMPLETE_PAYLOAD="{\"autoCompleteSetBy\":{\"id\":\"me\"},\"completionOptions\":{\"deleteSourceBranch\":true}}"
        fi
        
        curl -s \
            -X PATCH \
            -H "Authorization: Basic $(echo -n ":$AZURE_DEVOPS_EXT_PAT" | base64 -w 0)" \
            -H "Content-Type: application/json" \
            -d "$AUTO_COMPLETE_PAYLOAD" \
            "https://dev.azure.com/$ORGANIZATION/$PROJECT/_apis/git/repositories/$REPOSITORY/pullrequests/$PR_ID?api-version=7.1" > /dev/null
        echo "Auto-complete enabled."
    fi
else
    echo ""
    echo "Error: Failed to create pull request (HTTP $HTTP_CODE)"
    echo "Response: $RESPONSE_BODY"
    echo ""
    echo "Possible issues:"
    echo "  - Invalid AZURE_DEVOPS_EXT_PAT token or insufficient permissions"
    echo "  - Invalid organization, project, or repository settings"
    echo "  - Source branch not pushed to remote"
    echo "  - PR with same source/target already exists"
    echo "  - Invalid reviewer or work item IDs"
    exit 1
fi

