#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
use File::Basename qw/basename/;
use File::Find qw/find/;
use File::Path qw/mkpath/;
use File::Copy qw/copy/;
use Getopt::Long;
Getopt::Long::Configure("permute");

my ($verbose, $notorrent, $zeropad, $moveother, $output, $passkey, $tracker);

##############################################################
# whatmp3 - Convert FLAC to mp3, create what.cd torrent.
# Created by shardz (logik.li)
# Based on: Flac to Mp3 Perl Converter by Somnorific
# Which was based on: Scripts by Falkano and Nick Sklaventitis
##############################################################

my $VERSION = "2.3.2";

# Do you always want to move additional files (.jpg, .log, etc)?
$moveother = 1;

# Output folder unless specified: ("/home/samuel/Desktop/")
$output = "";

# Do you want to zeropad tracknumber values? (1 => 01, 2 => 02 ...)
$zeropad = 1;

# Specify torrent passkey
$passkey = "";

# Specify tracker ("http://tracker.what.cd:34000/")
$tracker = "http://tracker.what.cd:34000/";

# List of default encoding options, add to this list if you want more
my %enc_options = (
  "320"  => {enc => "lame", opts => "-b 320 --ignore-tag-errors"},
	"V0"   => {enc => "lame", opts => "-V 0 --vbr-new --ignore-tag-errors"},
	"V2"   => {enc => "lame", opts => "-V 2 --vbr-new --ignore-tag-errors"},
	"Q8"   => {enc => "oggenc", opts => "-q 8"},
	"ALAC" => {enc => "ffmpeg", opts => "-i - -acodec alac"},
);

###
# End of configuration
###

sub help {
	print<<__EOH__;
whatmp3 version $VERSION

Usage of $0:
	--320 --V2 --V0 --Q8 --ALAC ...
		encode to 320, V2, V0, or whatever else specified in 'enc_options' in the file
	--help
		print help message and quit
	--verbose
		increase verbosity (default false)
	--moveother
		move other files in flac directory to torrent directory (default true)
	--output="PATH"
		specify output directory for torrents
	--zeropad
		zeropad tracklists (default true)
	--passkey="PASSKEY"
		specify tracker passkey
	--tracker="TRACKER"
		specify tracker address to use (default "http://tracker.what.cd:34000")
	--notorrent
		do not generate a torrent file (default false)
	
Minimally, you need a passkey, a tracker, and an encoding option to create a 
working torrent to upload.

whatmp3 depends on metaflac, lame/oggenc, and mktorrent.
__EOH__
exit;
}

my (@enc_options, @flac_dirs);

ARG: foreach my $arg (@ARGV) {
	foreach my $opt (keys %enc_options) {
		if ($arg =~ m/\Q$opt/i) {
			push(@enc_options, $opt);
			next ARG;
		}
	}
}

sub process {
	my $arg = shift @_;
	chop($arg) if $arg =~ m'/$';
	push(@flac_dirs, $arg);
}

GetOptions('help' => \&help, 'verbose' => \$verbose, 'notorrent' => \$notorrent, 'zeropad', => \$zeropad, 'moveother' => \$moveother, 'output=s' => \$output, 'passkey=s' => \$passkey, 'tracker=s' => \$tracker, '<>' => \&process);

$output ||= "./";
$output =~ s'/?$'/' if $output;	# Add a missing /

unless (@flac_dirs) {
	print "Need FLAC file parameter\n";
	print "You can specify which lame encoding (V0, 320, ...) you want with --opt\n";
	exit 0;
}

# Store the lame options we actually want.

die "Need FLAC file parameter\n" unless @flac_dirs;

foreach my $flac_dir (@flac_dirs) {
	my (@files, @dirs);
	if ($flac_dir eq '.' or $flac_dir eq './') {
		$flac_dir = cwd;
	}
	find( sub { push(@files, $File::Find::name) if ($File::Find::name =~ m/\.flac$/i) }, $flac_dir);
	
	print "Using $flac_dir\n" if $verbose;
	
	foreach my $enc_option (@enc_options) {
		my $mp3_dir = $output . basename($flac_dir) . " ($enc_option)";
		$mp3_dir =~ s/FLAC//ig;
		mkpath($mp3_dir);
		
		print "\nEncoding with $enc_option started...\n" if $verbose;
	
		foreach my $file (@files) {
			$file =~ s/\$/\\\$/g;	# fix error with bash and $'s
			my (%tags, $mp3_filename);
			my $mp3_dir = $mp3_dir;	# localise changes to $mp3_dir so we don't affect subsequent mp3 directories
			if ($file =~ m!\Q$flac_dir\E/(.+)/.!) {
				$mp3_dir .= '/' . $1;
				mkpath($mp3_dir);
			}
	
			foreach my $tag (qw/TITLE ALBUM ARTIST TRACKNUMBER GENRE COMMENT DATE/) {
				($tags{$tag} = `metaflac --show-tag=$tag "$file" | awk -F = '{ printf(\$2) }'`) =~ s![:?/]!_!g;
				$tags{$tag} =~ s/\"/\\\"/g;	# fix error with escaping "'s
			}
			
			$tags{'TRACKNUMBER'} =~ s/^(?!0|\d{2,})/0/ if $zeropad;	# 0-pad tracknumbers, if desired.
	
			if ($tags{'TRACKNUMBER'} and $tags{'TITLE'}) {
				$mp3_filename = $mp3_dir . '/' . $tags{'TRACKNUMBER'} . " - " . $tags{'TITLE'};
			} else {
				my $basename = basename($file);
				$basename =~ s/\.[^.]+$//;
				$mp3_filename = $mp3_dir . '/' . $basename;
			}
	
			# Build the conversion script and do the actual conversion
			my $flac_command;
			if ($enc_options{$enc_option}->{'enc'} eq 'lame') {
				$flac_command = "flac -dc \"$file\" | lame " . $enc_options{$enc_option}->{'opts'} . ' ' .
					'--tt "' . $tags{'TITLE'} . '" ' .
					'--tl "' . $tags{'ALBUM'} . '" ' .
					'--ta "' . $tags{'ARTIST'} . '" ' .
					'--tn "' . $tags{'TRACKNUMBER'} . '" ' .
					'--tg "' . $tags{'GENRE'} . '" ' .
					'--ty "' . $tags{'DATE'} . '" ' .
					'--add-id3v2 - "' . $mp3_filename . '.mp3" 2>&1';
			} elsif ($enc_options{$enc_option}->{'enc'} eq 'oggenc') {
				$flac_command = "flac -dc \"$file\" | oggenc " . $enc_options{$enc_option}->{'opts'} . ' ' .
					'-t "' . $tags{'TITLE'} . '" ' .
					'-l "' . $tags{'ALBUM'} . '" ' .
					'-a "' . $tags{'ARTIST'} . '" ' .
					'-N "' . $tags{'TRACKNUMBER'} . '" ' .
					'-G "' . $tags{'GENRE'} . '" ' .
					'-d "' . $tags{'DATE'} . '" ' .
					'-o "' . $mp3_filename . '.ogg" - 2>&1';
			} elsif ($enc_options{$enc_option}->{'enc'} eq 'ffmpeg') {
				$flac_command = "flac -dc \"$file\" | ffmpeg " . $enc_options{$enc_option}->{'opts'} . ' ' .
					'-metadata title="' . $tags{'TITLE'} . '" ' .
					'-metadata album="' . $tags{'ALBUM'} . '" ' .
					'-metadata author="' . $tags{'ARTIST'} . '" ' .
					'-metadata track="' . $tags{'TRACKNUMBER'} . '" ' .
					'-metadata genre="' . $tags{'GENRE'} . '" ' .
					'-metadata date="' . $tags{'DATE'} . '"  "' .
					$mp3_filename . '.m4a" 2>&1';
			}
			$flac_command =~ s/\$/\\\$/g;	# fix error with bash and $'s
			print "$flac_command\n" if $verbose;
			system($flac_command);
		}
	
		print "\nEncoding with $enc_option finished...\n";
	
		if ($moveother) {
			print "Moving other files... " if $verbose;
		
			my $base_mp3_dir = basename($mp3_dir);
			find( { wanted => sub { 
				if ($File::Find::name !~ m/\.flac$/i and $File::Find::name !~ m!\Q$base_mp3_dir\E!) {
					if ($File::Find::name =~ m!\Q$flac_dir\E/(.+)/.!) {
						mkpath($mp3_dir . '/' . $1);
						copy($File::Find::name, $mp3_dir . '/' . $1);
					} else {
						copy($File::Find::name, $mp3_dir);
					}
				}
			}, no_chdir => 1 }, $flac_dir);
		}
	
		if ($output and $passkey and $tracker and not $notorrent) {
			print "\nCreating torrent... " if $verbose;
			my $torrent_create = 'mktorrent -p -a ' . $tracker . $passkey . '/announce -o "' . $output . basename($mp3_dir) . '.torrent" "' . $mp3_dir . '"';
			print "'$torrent_create'\n" if $verbose;
			system($torrent_create);
		}
	}
	print "\nAll done with $flac_dir...\n" if $verbose;
}
