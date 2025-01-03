#!/usr/bin/perl
#
# tfc-dump.pl - dump Terraform Cloud workspace and variable information
#
# Usage: tfc-dump.pl --org=org-name {--workspace=name | --all} [--quiet] [--help]
#
# For the supplied Terraform Cloud workspace name, dump the workspace
# and variable information in JSON format.
#
# A Terraform Cloud access token must be supplied in the ATLAS_TOKEN environment
# variable.  
#
# Uses curl(1), jq(1), tfc-ops(https://github.com/silinternational/tfc-ops).
# Version 3.0.0 of tfc-ops was used during development.
#
# SIL - GTIS
# December 2, 2022

use strict;
use warnings;
use Getopt::Long qw(GetOptions);

my $usage = "Usage: $0 --org=org-name {--workspace=name | --all} [--quiet] [--help]\n";
my $tfc_org_name;	# Terraform Cloud organization name
my $tfc_workspace_name;	# Terraform Cloud workspace name
my $tfc_workspace_id;	# Terraform Cloud workspace ID
my $all_workspaces;
my $quiet_mode;
my $help;

Getopt::Long::Configure qw(gnu_getopt);
GetOptions(
	'org|o=s'       => \$tfc_org_name,
	'workspace|w=s' => \$tfc_workspace_name,
	'all|a'         => \$all_workspaces,
	'quiet|q'       => \$quiet_mode,
	'help|h'        => \$help
) or die $usage;

die $usage if (!defined($tfc_org_name) || defined($help));
die $usage if ( defined($tfc_workspace_name) &&  defined($all_workspaces));	# can't have both
die $usage if (!defined($tfc_workspace_name) && !defined($all_workspaces));	# must have one

if (! $ENV{ATLAS_TOKEN}) {
	print STDERR "Terraform Cloud access token must be in ATLAS_TOKEN environment variable.\n";
	die $usage;
}

my $curl_header1 = "--header \"Authorization: Bearer $ENV{ATLAS_TOKEN}\"";
my $curl_header2 = "--header \"Content-Type: application/vnd.api+json\"";
my $curl_headers = "$curl_header1 $curl_header2";
if (defined($quiet_mode)) {
	$curl_headers .= " --no-progress-meter";
}
my $curl_query;
my $curl_cmd;
my $jq_cmd;
my %workspace_list;
if (defined($tfc_workspace_name)) {	# One workspace desired

	# Get the workspace ID given the workspace name.

	$curl_query = "\"https://app.terraform.io/api/v2/organizations/${tfc_org_name}/workspaces/${tfc_workspace_name}\"";
	$curl_cmd   = "curl $curl_headers $curl_query";
	$jq_cmd     = "jq '.data.id'";

	$tfc_workspace_id = `$curl_cmd | $jq_cmd`;
	$tfc_workspace_id =~ s/"//g;
	chomp($tfc_workspace_id);

	$workspace_list{$tfc_workspace_name} = $tfc_workspace_id;
}
else {	# All workspaces desired
	my $tfc_ops_cmd = "tfc-ops workspaces list --organization ${tfc_org_name} --attributes name,id";

	my @result = `$tfc_ops_cmd`;

	# tfc-ops prints two header lines before the data we want to see.
	shift(@result);		# remove "Getting list of workspaces ..."
	shift(@result);		# remove "name, id"
	chomp(@result);		# remove newlines

	my $name;
	my $id;
	foreach (@result) {
		($name, $id) = split(/, /, $_);
		$workspace_list{$name} = $id;
	}
}

# Dump the workspace and variable data to files.

foreach (sort keys %workspace_list) {

	# Dump the workspace info
	$curl_query = "\"https://app.terraform.io/api/v2/workspaces/$workspace_list{$_}\"";
	$curl_cmd   = "curl $curl_headers --output $_-attributes.json $curl_query";
	system($curl_cmd);

	# Dump the variables info
	$curl_query = "\"https://app.terraform.io/api/v2/workspaces/$workspace_list{$_}/vars\"";
	$curl_cmd   = "curl $curl_headers --output $_-variables.json $curl_query";
	system($curl_cmd);
}

# Dump the variable sets data to files.

### WARNING ###
#
# This code assumes that all of the TFC Variable Sets are contained within
# the first result page of 100 entries.  This was true for SIL in August 2024.
#
####

my @vs_names;
my @vs_ids;
my $pg_size = 100;
my $pg_num = 1;
my $total_count;
my $items_processed = 0;
my $tmpfile = `mktemp`;
chomp($tmpfile);

# Get all variable sets across pages
do {
	$curl_query = "\"https://app.terraform.io/api/v2/organizations/${tfc_org_name}/varsets?page%5Bsize%5D=${pg_size}&page%5number%5D=${pg_num}\"";
	$curl_cmd   = "curl $curl_headers --output $tmpfile $curl_query";
	system($curl_cmd);

# Get the Variable Set names for this page
	$jq_cmd   = "cat $tmpfile | jq '.data[].attributes.name'";
	my @page_names = `$jq_cmd`;
	@page_names = map { s/"//gr } @page_names;
	chomp(@page_names);
	push(@vs_names, @page_names);

# Get the Variable Set IDs for this page
    $jq_cmd = "cat $tmpfile | jq '.data[].id'";
    my @page_ids = `$jq_cmd`;
    @page_ids = map { s/"//gr } @page_ids;
    chomp(@page_ids);
    push(@vs_ids, @page_ids);

# Update counts
    my $page_items = scalar(@page_ids);
    $items_processed += $page_items;

# Get total count from pagination metadata if not already set
if ($total_count == 0) {
	$jq_cmd = "cat $tmpfile | jq '.meta.pagination[\"total-count\"]'";
    $total_count = `$jq_cmd`;
    chomp($total_count);
}

# Provide Feedback
print "Processed $items_processed of $total_count Variable Set\n" unless $quiet_mode;
$pg_num++;
} while ($items_processed < $total_count);

# Process the variable sets
my $filename;
for (my $ii = 0; $ii < scalar @vs_names; $ii++) {
	$filename = $vs_names[$ii];
	$filename =~ s/ /-/g;	# replace spaces with hyphens

# Get the Variable Set
	$curl_query = "\"https://app.terraform.io/api/v2/varsets/$vs_ids[$ii]\"";
	$curl_cmd   = "curl $curl_headers --output varset-${filename}-attributes.json $curl_query";
	system($curl_cmd);

# Get the variables within the Variable Set
	$curl_query = "\"https://app.terraform.io/api/v2/varsets/$vs_ids[$ii]/relationships/vars\"";
	$curl_cmd   = "curl $curl_headers --output varset-${filename}-variables.json $curl_query";
	system($curl_cmd);
}

unlink($tmpfile);

# Provide final status
if ($items_processed != $total_count) {
    print STDERR "WARNING: Only processed ${items_processed} of ${total_count} Variable Sets.\n";
    exit(1);
} else {
    print "Successfully processed all ${total_count} Variable Sets\n" unless $quiet_mode;
}
exit(0);
