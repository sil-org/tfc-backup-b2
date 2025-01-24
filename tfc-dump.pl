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

# Function to log errors to Sentry
sub error_to_sentry {
    my ($message) = @_;
    system("sentry-cli send-event \"$message\" 2>/dev/null") if $ENV{SENTRY_DSN};
}

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
    my $error = "Terraform Cloud access token must be in ATLAS_TOKEN environment variable.";
    error_to_sentry($error);
    print STDERR "$error\n";
    die $usage;
}

my $curl_header1 = "--header \"Authorization: Bearer $ENV{ATLAS_TOKEN}\"";
my $curl_header2 = "--header \"Content-Type: application/vnd.api+json"";
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

    system("$curl_cmd | $jq_cmd > /tmp/workspace_id.txt");
    $tfc_workspace_id = do {
        local(@ARGV, $/) = '/tmp/workspace_id.txt';
        <>;
    };
    system("rm -f /tmp/workspace_id.txt");
    if ($?) {
        my $error = "Failed to get workspace ID for $tfc_workspace_name";
        error_to_sentry($error);
        die "$error\n";
    }
    $tfc_workspace_id =~ s/"//g;
    chomp($tfc_workspace_id);

    $workspace_list{$tfc_workspace_name} = $tfc_workspace_id;
}
else {	# All workspaces desired
    my $tfc_ops_cmd = "tfc-ops workspaces list --organization ${tfc_org_name} --attributes name,id";

    system("$tfc_ops_cmd > /tmp/tfc_ops_result.txt");
    my @result = do {
        local(@ARGV, $/) = '/tmp/tfc_ops_result.txt';
        <>;
    };
    system("rm -f /tmp/tfc_ops_result.txt");
    if ($?) {
        my $error = "Failed to list workspaces";
        error_to_sentry($error);
        die "$error\n";
    }

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
    if (system($curl_cmd) != 0) {
        my $error = "Failed to dump workspace attributes for $_";
        error_to_sentry($error);
        print STDERR "$error\n";
    }

    # Dump the variables info
    $curl_query = "\"https://app.terraform.io/api/v2/workspaces/$workspace_list{$_}/vars\"";
    $curl_cmd   = "curl $curl_headers --output $_-variables.json $curl_query";
    if (system($curl_cmd) != 0) {
        my $error = "Failed to dump workspace variables for $_";
        error_to_sentry($error);
        print STDERR "$error\n";
    }
}

# Dump the variable sets data to files.
my @vs_names;
my @vs_ids;
my $pg_size = 20;  # Default page size per Hashicorp documentation
my $pg_num = 1;    # Start with page 1
my $total_count;
my $total_processed = 0;
my $tmpfile;
system("mktemp > /tmp/tmpfile.txt");
$tmpfile = do {
    local(@ARGV, $/) = '/tmp/tmpfile.txt';
    <>;
};
system("rm -f /tmp/tmpfile.txt");
chomp($tmpfile);

do {
    # Get the current page of variable sets
    $curl_query = "\"https://app.terraform.io/api/v2/organizations/${tfc_org_name}/varsets?page%5Bsize%5D=${pg_size}&page%5Bnumber%5D=${pg_num}\"";
    $curl_cmd = "curl $curl_headers --output $tmpfile $curl_query";
    
    if (system($curl_cmd) != 0) {
        my $error = "Failed to fetch variable sets page $pg_num";
        error_to_sentry($error);
        print STDERR "$error\n";
        last;
    }

    # Get the Variable Set names for this page
    $jq_cmd = "cat $tmpfile | jq '.data[].attributes.name'";
    system("$jq_cmd > /tmp/page_names.txt");
    my @page_names = do {
        local(@ARGV, $/) = '/tmp/page_names.txt';
        <>;
    };
    system("rm -f /tmp/page_names.txt");
    @page_names = map { s/"//gr } @page_names;
    chomp(@page_names);
    push(@vs_names, @page_names);

    # Get the Variable Set IDs for this page
    $jq_cmd = "cat $tmpfile | jq '.data[].id'";
    system("$jq_cmd > /tmp/page_ids.txt");
    my @page_ids = do {
        local(@ARGV, $/) = '/tmp/page_ids.txt';
        <>;
    };
    system("rm -f /tmp/page_ids.txt");
    @page_ids = map { s/"//gr } @page_ids;
    chomp(@page_ids);
    push(@vs_ids, @page_ids);

    # Get total count if we haven't yet
    if (!defined($total_count)) {
        $jq_cmd = "cat $tmpfile | jq '.meta.pagination[\"total-count\"]'";
        system("$jq_cmd > /tmp/total_count.txt");
        $total_count = do {
            local(@ARGV, $/) = '/tmp/total_count.txt';
            <>;
        };
        system("rm -f /tmp/total_count.txt");
        chomp($total_count);
        print "Total variable sets to process: $total_count\n" unless defined($quiet_mode);
    }

    $total_processed += scalar(@page_names);
    print "Processed $total_processed of $total_count variable sets\n" unless defined($quiet_mode);

    $pg_num++;
} while ($total_processed < $total_count);

# Verify we got everything we expected
if ($total_processed != $total_count) {
    my $error = "Warning: Expected $total_count variable sets but processed $total_processed";
    error_to_sentry($error);
    print STDERR "$error\n";
}

print "Successfully processed all $total_count variable sets\n" unless defined($quiet_mode);

my $filename;
for (my $ii = 0; $ii < scalar @vs_names; $ii++) {
    $filename = $vs_names[$ii];
    $filename =~ s/ /-/g;    # replace spaces with hyphens

    # Get the Variable Set
    $curl_query = "\"https://app.terraform.io/api/v2/varsets/$vs_ids[$ii]\"";
    $curl_cmd = "curl $curl_headers --output varset-${filename}-attributes.json $curl_query";
    if (system($curl_cmd) != 0) {
        my $error = "Failed to dump varset attributes for $filename";
        error_to_sentry($error);
        print STDERR "$error\n";
    }

    # Get the variables within the Variable Set
    $curl_query = "\"https://app.terraform.io/api/v2/varsets/$vs_ids[$ii]/relationships/vars\"";
    $curl_cmd = "curl $curl_headers --output varset-${filename}-variables.json $curl_query";
    if (system($curl_cmd) != 0) {
        my $error = "Failed to dump varset variables for $filename";
        error_to_sentry($error);
        print STDERR "$error\n";
    }
}

unlink($tmpfile);
exit(0);
