# Terraform PR Commenter

This Composite Github-Action is designed to work with [hashicorp/setup-terraform](https://github.com/hashicorp/setup-terraform) with the wrapper enabled, taking the output from a `plan` formatting it and adding it to a pull request.

Any previous comments from this Action are removed to keep the PR timeline clean.

Pass following variable as environment variables in a workflow:

- GITHUB_TOKEN
- GITHUB_EVENT_PATH
- GITHUB_REPOSITORY
- GITHUB_RUN_ID
- ACTION_OUTPUT
- ACTION_EXITCODE

## Usage

```yaml
- name: Terraform Plan
  id: plan
  shell: bash
  run: terraform plan

- name: Post Plan
  env:
    GITHUB_TOKEN: ${{secrets.GITHUB_TOKEN}}
    GITHUB_EVENT_PATH: ${{github.event_path}}
    GITHUB_REPOSITORY: ${{github.repository}}
    GITHUB_RUN_ID: ${{github.run_id}}
    ACTION_OUTPUT: ${{ format('{0}{1}', steps.plan.outputs.stdout, steps.plan.outputs.stderr) }}
    ACTION_EXITCODE: ${{ steps.plan.outputs.exitcode }}
  uses: vikram-katkar-discovery/terraform-pr-commenter@main
```