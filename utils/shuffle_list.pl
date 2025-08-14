#!/usr/bin/perl
# Copyright 2019 Hitachi, Ltd. (author: Yusuke Fujita)
# Licensed under the MIT license.
#
# This script shuffles a list with a specified seed.
# Usage: shuffle_list.pl [--srand <seed>] < <input-file> > <output-file>

use strict;
use warnings;

my $seed = 0;

# Parse command line arguments
while (@ARGV > 0) {
    my $arg = shift @ARGV;
    if ($arg eq '--srand') {
        $seed = shift @ARGV;
    } else {
        die "Unknown option: $arg\n";
    }
}

# Set random seed
srand($seed);

# Read all lines
my @lines = <STDIN>;
chomp @lines;

# Shuffle the lines
for (my $i = @lines - 1; $i > 0; $i--) {
    my $j = int(rand($i + 1));
    @lines[$i, $j] = @lines[$j, $i];
}

# Output shuffled lines
print join("\n", @lines) . "\n"; 