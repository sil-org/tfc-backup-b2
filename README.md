# tfc-backup-b2
Docker image to export variables from Terraform Cloud and back them up to a
Restic repository on Backblaze B2.
The image can also initialize the Restic repository on the existing
Backblaze B2 bucket.

## Description
During the review of a disaster recovery plan, we realized that we didn't have
a record of the values we set for variables in Terraform Cloud workspaces.
It would be difficult to recover from the accidental deletion of a Terraform
Cloud workspace.
A Perl script exports workspaces, variables, and variable sets to JSON files
using the Terraform Cloud API.
The JSON files are then backed up using Restic to a repository on a Backblaze
B2 bucket.

Two files are created for each Terraform Cloud workspace:

- _workspace-name_-attributes.json
- _workspace-name_-variables.json

Two files are created for each Terraform Cloud Variable Set:

- varset-_variable-set-name_-attributes.json
- varset-_variable-set-name_-variables.json

Spaces in the variable set name are replaced with hyphens (`-`).

## How to use it

1. Copy `local.env.dist` to `local.env`.
1. Set the values for the variables contained in `local.env`.
1. Obtain a Terraform Cloud access token. Go to [https://app.terraform.io/app/settings/tokens](https://app.terraform.io/app/settings/tokens) to create an API token.
1. Add the access token as the value for `ATLAS_TOKEN` in `local.env`.
1. Create a Backblaze B2 bucket. Set the `File Lifecycle` to `Keep only the last version`.
1. Add the B2 bucket name to `RESTIC_REPOSITORY` in `local.env`.
1. Obtain a Backblaze Application Key. Restrict its access to the B2 bucket you just created. Ensure the application key has these capabilities: `deleteFiles`, `listBuckets`, `listFiles`, `readBuckets`, `readFiles`, `writeBuckets`, `writeFiles`.
1. Add the application key and secret to `local.env` as the values of `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY` respectively.
1. Initialize the Restic repository (one time only):  `docker run --env-file=local.env --env BACKUP_MODE=init silintl/tfc-backup-b2:latest`
1. Run the Docker image:  `docker run --env-file=local.env silintl/tfc-backup-b2:latest`

### Variables

* `ATLAS_TOKEN`        - Terraform Cloud access token
* `B2_ACCOUNT_ID`      - Backblaze keyID
* `B2_ACCOUNT_KEY`     - Backblaze applicationKey
* `FSBACKUP_MODE`      - `init` initializes the Restic repository at `$RESTIC_REPOSITORY` (only do this once), `backup` performs a backup
* `ORGANIZATION`       - Name of the Terraform Cloud organization to be backed up
* `RESTIC_BACKUP_ARGS` - additional arguments to pass to `restic backup` command
* `RESTIC_FORGET_ARGS` - additional arguments to pass to `restic forget --prune` command (e.g., `--keep-daily 7 --keep-weekly 5  --keep-monthly 3 --keep-yearly 2`)
* `RESTIC_HOST`        - hostname to be used for the backup
* `RESTIC_PASSWORD`    - password for the Restic repository
* `RESTIC_REPOSITORY`  - Restic repository location (e.g., `b2:bucketname:restic`)
* `RESTIC_TAG`         - tag to apply to the backup
* `SOURCE_PATH`        - Full path to the directory to be backed up

## Restrictions
The code assumes that all of the Terraform Cloud Variable Sets are contained
within the first result page of 100 entries.

## Docker Hub
This image is built automatically on Docker Hub as [silintl/tfc-backup-b2](https://hub.docker.com/r/silintl/tfc-backup-b2/)

