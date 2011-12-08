#!/usr/bin/env perl

use strict;
use warnings;
use POSIX qw(setsid);
use File::Basename;
use Getopt::Long;
use Net::SMTP;
use Net::SMTP::Server;
use Net::SMTP::Server::Client;
use Net::DNS;

sub usage() {
	print STDERR "Usage: $0 [-d|--daemon] [-h|--host <listen_host>] [-p|--port <listen_port>] <recipient\@example.net> [<smtp_host[:port]>]\n";
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
my $ret = GetOptions(
	'h|host=s' => \$listen_host,
	'p|port=s' => \$listen_port,
	'd|daemon' => \$run_as_daemon
	);
if( ! $ret ) {
	die usage();
}

my $to = shift || die usage();
my $smtp_host = shift;
if( not defined $smtp_host ) {
	my $res = Net::DNS::Resolver->new;
	my ($domain) = ($to =~ m/^.*@([^@]+)$/);
	my @mx = mx($res, $domain);
	die sprintf("Error: could not find MXs for domain '%s'!\n", $domain) if( $#mx <= 0 );
	$smtp_host = $mx[0]->exchange;
}

my $server = new Net::SMTP::Server($listen_host, $listen_port);
if( not $server ) {
	die sprintf("Error: could not start SMTP server on <%s:%s>: %s\n", $listen_host, $listen_port, $!);
}
if( $run_as_daemon ) {
	daemonize();
}
print STDERR sprintf("Waiting for Godot on <%s:%s>...\n", $listen_host, $listen_port);

my ($conn, $client, $smtp);
while( $conn = $server->accept() ) {
	$client = new Net::SMTP::Server::Client($conn);
	if( not $client ) {
		print STDERR sprintf("Error: could not get client: %s\n", $!);;
		next;
	}
	$client->process || next;
	print STDERR sprintf("Relaying message from '%s' to '%s' via '%s' (original recipient = '%s')... ", $client->{FROM}, $to, $smtp_host, join(', ', @{ $client->{TO} }));
	$smtp = new Net::SMTP($smtp_host, Timeout => 60);
	$smtp->mail($client->{FROM});
	$smtp->to($to);
	$smtp->data($client->{MSG});
	$smtp->dataend();
	$smtp->quit();
	print STDERR sprintf("Done.\n");
}
