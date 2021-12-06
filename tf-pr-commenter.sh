#!/usr/bin/env bash

#############
# Validations
#############
PR_NUMBER=$(jq -r ".pull_request.number" "$GITHUB_EVENT_PATH")
if [[ "$PR_NUMBER" == "null" ]]; then
	echo "This isn't a PR."
	exit 0
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
	echo "GITHUB_TOKEN environment variable missing."
	exit 1
fi

if [[ -z "$ACTION_EXITCODE" ]]; then
    echo "There must be an exit code from a previous step."
    exit 1
fi

##################
# Shared Variables
##################
# Arg 1 is command
COMMAND="$ACTION_TYPE"
# Arg 2 is input. We strip ANSI colours.
INPUT=$(echo "$ACTION_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
echo -e "\033[34;1mINFO:\033[0m Input ${INPUT}."
# Arg 3 is the Terraform CLI exit code
EXIT_CODE="$ACTION_EXITCODE"
echo -e "\033[34;1mINFO:\033[0m Exit code ${EXIT_CODE}."

# Read TF_WORKSPACE environment variable or use "default"
WORKSPACE=${TF_WORKSPACE:-default}

# Read EXPAND_SUMMARY_DETAILS environment variable or use "true"
if [[ ${EXPAND_SUMMARY_DETAILS:-true} == "true" ]]; then
  DETAILS_STATE=" open"
else
  DETAILS_STATE=""
fi

# Read HIGHLIGHT_CHANGES environment variable or use "true"
COLOURISE=${HIGHLIGHT_CHANGES:-true}

ACCEPT_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
CONTENT_HEADER="Content-Type: application/json"

PR_COMMENTS_URL=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
PR_COMMENT_URI=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")

###############
# Handler: plan
###############
if [[ $COMMAND == 'plan' ]]; then
  # Look for an existing plan PR comment and delete
  echo -e "\033[34;1mINFO:\033[0m Looking for an existing plan PR comment."
  PR_COMMENT_ID=$(curl -sS -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENTS_URL" | jq '.[] | select(.body|test ("### Terraform `plan` .* for Workspace: `'"$WORKSPACE"'`")) | .id')
  if [ "$PR_COMMENT_ID" ]; then
    echo -e "\033[34;1mINFO:\033[0m Found existing plan PR comment: $PR_COMMENT_ID. Deleting."
    PR_COMMENT_URL="$PR_COMMENT_URI/$PR_COMMENT_ID"
    curl -sS -X DELETE -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -L "$PR_COMMENT_URL" > /dev/null
  else
    echo -e "\033[34;1mINFO:\033[0m No existing plan PR comment found."
  fi

  # Exit Code: 0, 2
  # Meaning: 0 = Terraform plan succeeded with no changes. 2 = Terraform plan succeeded with changes.
  # Actions: Strip out the refresh section, ignore everything after the 72 dashes, format, colourise and build PR comment.
  if [[ $EXIT_CODE -eq 0 || $EXIT_CODE -eq 2 ]]; then
    CLEAN_PLAN=$(echo "$INPUT" | sed -r '/^(An execution plan has been generated and is shown below.|Terraform used the selected providers to generate the following execution|No changes. Infrastructure is up-to-date.|No changes. Your infrastructure matches the configuration.|Note: Objects have changed outside of Terraform)$/,$!d') # Strip refresh section
    PLAN_SUMMARY=$(echo "$CLEAN_PLAN" | sed -n '/^Plan: /p') # Plan summary line
    CLEAN_PLAN=$(echo "$CLEAN_PLAN" | sed -r '/Plan: /q') # Ignore everything after plan summary
    echo -e "\033[34;1mINFO:\033[0m Total characters are ${#CLEAN_PLAN}."
    if [[ ${#CLEAN_PLAN} -le 65000 ]]; then
    # CLEAN_PLAN=${CLEAN_PLAN::65300} # GitHub has a 65535-char comment limit - truncate plan, leaving space for comment wrapper
    CLEAN_PLAN=$(echo "$CLEAN_PLAN" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line
    if [[ $COLOURISE == 'true' ]]; then
      CLEAN_PLAN=$(echo "$CLEAN_PLAN" | sed -r 's/^~/!/g') # Replace ~ with ! to colourise the diff in GitHub comments
    fi
    PR_COMMENT="### Terraform \`plan\` Succeeded for Workspace: \`$WORKSPACE\`
<details$DETAILS_STATE><summary>$PLAN_SUMMARY</summary>

\`\`\`diff
$CLEAN_PLAN
\`\`\`
</details>"
    else
      PR_COMMENT="### Terraform \`plan\` Succeeded for Workspace: \`$WORKSPACE\`
$PLAN_SUMMARY
Output is too long to show in PR comment. Please visit [logs](https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID)."
    fi
  fi

  # Exit Code: 1
  # Meaning: Terraform plan failed.
  # Actions: Build PR comment.
  if [[ $EXIT_CODE -eq 1 ]]; then
    PR_COMMENT="### Terraform \`plan\` Failed for Workspace: \`$WORKSPACE\`
<details$DETAILS_STATE><summary>Show Output</summary>

\`\`\`
$INPUT
\`\`\`
</details>"
  fi

  # Add plan comment to PR.
  PR_PAYLOAD=$(echo '{}' | jq --arg body "$PR_COMMENT" '.body = $body')
  echo -e "\033[34;1mINFO:\033[0m Adding plan comment to PR."
  curl -sS -X POST -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" -H "$CONTENT_HEADER" -d "$PR_PAYLOAD" -L "$PR_COMMENTS_URL" > /dev/null

  exit 0
fi