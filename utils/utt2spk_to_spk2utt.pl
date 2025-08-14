#!/usr/bin/perl
# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
# Licensed under the MIT license.
#
# This script converts utt2spk to spk2utt format.
# Usage: utt2spk_to_spk2utt.pl <utt2spk_file> > <spk2utt_file>

use strict;
use warnings;

if (@ARGV != 1) {
    die "Usage: $0 <utt2spk_file>\n";
}

my $utt2spk_file = $ARGV[0];

# Read utt2spk file and build spk2utt mapping
my %spk2utt = ();

open(my $fh, '<', $utt2spk_file) or die "Cannot open $utt2spk_file: $!\n";

while (my $line = <$fh>) {
    chomp $line;
    my ($utt, $spk) = split(/\s+/, $line, 2);
    if (defined($spk)) {
        push @{$spk2utt{$spk}}, $utt;
    }
}

close($fh);

# Output spk2utt format
foreach my $spk (sort keys %spk2utt) {
    print "$spk " . join(" ", @{$spk2utt{$spk}}) . "\n";
} 