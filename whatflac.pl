#!/usr/bin/perl

################################################################################
#
# whatflac - Transcode FLAC files and create torrent.
#
# Copyright (C) 2013  stfn <stfnmd@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################
#
# Historically based on:
#
# 	- whatmp3 by shardz (logik.li)
# 	- Flac to Mp3 Perl Converter by Somnorific
#	- Scripts by Falkano and Nick Sklaventitis
#
################################################################################

use strict;
use warnings;

use Cwd;
use File::Basename qw/basename/;
use File::Find qw/find/;
use File::Path qw/mkpath/;
use File::Copy qw/copy/;
use Getopt::Long;
Getopt::Long::Configure("permute");

my ($OPT_VERBOSE, $OPT_NOTORRENT, $OPT_ZEROPAD, $OPT_MOVEOTHER, $OPT_OUTPUT, $OPT_PASSKEY, $OPT_TRACKER);

my $VERSION = "1.0";

# Do you always want to move additional files (.jpg, .log, etc)?
$OPT_MOVEOTHER = 0;

# Output folder unless specified: ("/home/samuel/Desktop/")
$OPT_OUTPUT = "";

# Do you want to zeropad tracknumber values? (1 => 01, 2 => 02 ...)
$OPT_ZEROPAD = 1;

# Specify torrent passkey
$OPT_PASSKEY = "";

# Specify tracker ("http://tracker.what.cd:34000/")
$OPT_TRACKER = "http://tracker.what.cd:34000/";

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
whatflac version $VERSION

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

whatflac depends on flac, metaflac, lame/oggenc, and mktorrent.
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

GetOptions('help' => \&help, 'verbose' => \$OPT_VERBOSE, 'notorrent' => \$OPT_NOTORRENT, 'zeropad', => \$OPT_ZEROPAD, 'moveother' => \$OPT_MOVEOTHER, 'output=s' => \$OPT_OUTPUT, 'passkey=s' => \$OPT_PASSKEY, 'tracker=s' => \$OPT_TRACKER, '<>' => \&process);

$OPT_OUTPUT ||= "./";
$OPT_OUTPUT =~ s'/?$'/' if $OPT_OUTPUT;	# Add a missing /

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
	
	print "Using $flac_dir\n" if $OPT_VERBOSE;
	
	foreach my $enc_option (@enc_options) {
		my $mp3_dir = $OPT_OUTPUT . basename($flac_dir) . " ($enc_option)";
		$mp3_dir =~ s/FLAC//ig;
		mkpath($mp3_dir);
		
		print "\nEncoding with $enc_option started...\n" if $OPT_VERBOSE;
	
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
			
			$tags{'TRACKNUMBER'} =~ s/^(?!0|\d{2,})/0/ if $OPT_ZEROPAD;	# 0-pad tracknumbers, if desired.
	
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
			print "$flac_command\n" if $OPT_VERBOSE;
			system($flac_command);
		}
	
		print "\nEncoding with $enc_option finished...\n";
	
		if ($OPT_MOVEOTHER) {
			print "Moving other files... " if $OPT_VERBOSE;
		
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
	
		if ($OPT_OUTPUT and $OPT_PASSKEY and $OPT_TRACKER and not $OPT_NOTORRENT) {
			print "\nCreating torrent... " if $OPT_VERBOSE;
			my $torrent_create = 'mktorrent -p -a ' . $OPT_TRACKER . $OPT_PASSKEY . '/announce -o "' . $OPT_OUTPUT . basename($mp3_dir) . '.torrent" "' . $mp3_dir . '"';
			print "'$torrent_create'\n" if $OPT_VERBOSE;
			system($torrent_create);
		}
	}
	print "\nAll done with $flac_dir...\n" if $OPT_VERBOSE;
}
