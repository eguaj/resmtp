#!/usr/bin/env perl

use strict;
use warnings;
use POSIX qw(setsid strftime);
use File::Basename;
use Getopt::Long;
use Net::SMTP;
use Net::SMTP::Server;
use Net::SMTP::Server::Client;
use Net::DNS;

sub usage() {
	print STDERR "Usage: $0 [-d|--daemon] [-h|--host <listen_host>] [-p|--port <listen_port>] [-t|--timeout <timeout_in_seconds>] [-b|--blackhole] [-f|--from <smtp-from\@example.net>] <recipient\@example.net>[,<recipient2\@example.net>,[...]] [<smtp_host[:port]>]\n";
}

sub daemonize {
	$0 = File::Basename::basename($0);
	chdir '/'               or die "Can't chdir to /: $!";
	open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
	open STDOUT, '>/dev/null'
		       or die "Can't write to /dev/null: $!";
	defined(my $pid = fork) or die "Can't fork: $!";
	exit if $pid;
	die "Can't start a new session: $!" if setsid == -1;
	open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
}

my $listen_host = 'localhost';
my $listen_port = 25;
my $run_as_daemon = 0;
my $timeout = 15;
my $blackhole = 0;
my $from = undef;
my $ret = GetOptions(
	'h|host=s' => \$listen_host,
	'p|port=s' => \$listen_port,
	'd|daemon' => \$run_as_daemon,
	't|timeout=i' => \$timeout,
	'b|blackhole' => \$blackhole,
	'f|from=s' => \$from
	);
if( ! $ret ) {
	die usage();
}

my ($recipients, $smtp_host);
if( not $blackhole ) {
	$recipients = shift || die usage();
	$smtp_host = shift;
}
my @recipientList = split(/\s*,\s*/, $recipients);

my $server = new Net::SMTP::Server($listen_host, $listen_port);
if( not $server ) {
	die sprintf("Error: could not start SMTP server on <%s:%s>: %s\n", $listen_host, $listen_port, $!);
}
if( $run_as_daemon ) {
	daemonize();
}
print STDERR sprintf("Waiting for Godot on <%s:%s>...\n", $listen_host, $listen_port);

my ($conn, $client, $smtp, $msg, $headers, $body);
while( $conn = $server->accept() ) {
	$client = new Net::SMTP::Server::Client($conn);
	if( not $client ) {
		print STDERR sprintf("Error: could not get client: %s\n", $!);;
		next;
	}
	$client->process || next;
	if( $blackhole ) {
		print STDERR sprintf("%s Blackholing message from '%s' (original recipient = '%s')... Done.\n", strftime("%FT%T%z", localtime(time())), $client->{FROM}, join(', ', @{ $client->{TO} }));
		next;
	}

	$msg = $client->{MSG};
	if (defined $from) {
		($headers, $body) = ($msg =~ m/^(.*?)(\r?\n\r?\n.*)$/ms);
		$headers =~ s/^From:\s*(.+(?:\r?\n\s+.+)*)/From: $from\nX-Original-From: $1/m;
		$msg = $headers . $body;
	} else {
		$from = $client->{FROM};
	}

	foreach my $to (@recipientList) {
		my $recipient_smtp_host = $smtp_host;
		if( not defined $recipient_smtp_host ) {
			my $res = Net::DNS::Resolver->new;
			my ($domain) = ($to =~ m/^.*@([^@]+)$/);
			my @mx = mx($res, $domain);
			die sprintf("Error: could not find MXs for domain '%s'!\n", $domain) if( $#mx <= 0 );
			$recipient_smtp_host = $mx[0]->exchange;
		}

		print STDERR sprintf("%s Relaying message from '%s' to '%s' via '%s' (original recipient = '%s')... ", strftime("%FT%T%z", localtime(time())), $client->{FROM}, $to, $recipient_smtp_host, join(', ', @{ $client->{TO} }));
		$smtp = new Net::SMTP($recipient_smtp_host, Timeout => $timeout);
		if( not $smtp) {
			print STDERR sprintf("Error: could not connect to SMTP host '%s': %s\n", $recipient_smtp_host, $!);
			next;
		}
		$smtp->mail($from);
		$smtp->to($to);
		$smtp->data($msg);
		$smtp->dataend();
		$smtp->quit();
		print STDERR sprintf("Done.\n");
	}
}
