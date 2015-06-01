#!/usr/bin/perl
#
# HPVM disk physical/virtual mapping script
#
# This is a short script to create a physical (host)/virtual (guest) map.
# This is a basic script written quickly, that was used to simplify data migration operations. So improvements welcomed.
#
#    Requirements :
#
#    script must be run from host. (not guest)
#    ssh must be allowed using keys (no passwd) to all guests.
#    hpvmstatus command must be available from path.
#
# Author(s): uggla@free.fr   
#
# References: http://uggla.free.fr/wordpress/?p=811
#
# vim:expandtab:tw=80:ts=4:ft=help:norl:syntax=perl:

use strict;
use warnings;
use Data::Dumper;

my @hpvmstatus=`hpvmstatus`;
my @vms;
my $vm;

my %vm_data;

foreach(@hpvmstatus) {
    ($vm)=$_ =~ /^(.+)\s+[0-9]+\sHPUX\s+On/;
    if (defined($vm)) {
        $vm =~ s/\s+//g;
        push (@vms,$vm);
    }
}

foreach $vm (@vms){
    my @hpvmstatus_vm = `hpvmstatus -P $vm`;

    foreach(@hpvmstatus_vm){
        # Device  Adaptor    Bus Dev Ftn Tgt Lun Storage   Device
        # ======= ========== === === === === === ========= =========================
        # disk    avio_stor    0   2   0   0   0 disk      /dev/rdisk/disk17

        (my $ftn,my $tgt,my $lun,my $disk) = $_ =~ /^disk\s+avio_stor\s+\d+\s+\d+\s+(\d+)\s+(\d+)\s+(\d+)\s+disk\s+(.+)$/;

        if ( defined($ftn) ) {
            $vm_data{$vm}->{$disk}->{"dev"} = $ftn;
            $vm_data{$vm}->{$disk}->{"tgt"} = $tgt;
            $vm_data{$vm}->{$disk}->{"lun"} = $lun;

            # Convert tgt to the good legacy device
            my $tgtconv = sprintf("%02X",$tgt);
            my $tgtconv_part1;
            my $tgtconv_part2;

            ($tgtconv_part1) = $tgtconv =~/(.)./;
            ($tgtconv_part2) = $tgtconv =~/.(.)/;

            $tgtconv_part1=hex($tgtconv_part1);
            $tgtconv_part2=hex($tgtconv_part2);

            #$vm_data{$vm}->{$disk}->{"legacy"}="c".$ftn."t".$tgtconv_part2."d".$tgtconv_part1;
            $vm_data{$vm}->{$disk}->{"legacy"}="c\\dt".$tgtconv_part2."d".$tgtconv_part1; # Don't know how the instance number is defined (cX) so use a more gereric regexp
        }
    }
}

foreach $vm (@vms) {
    my @ioscan=`ssh -q -o stricthostkeychecking=no -o batchmode=yes root\@$vm \"ioscan -m dsf\"`;

    foreach( keys(%{$vm_data{$vm}}) ) {
        my $regex = $vm_data{$vm}->{$_}->{"legacy"}."\$";
        my @vdisk = grep(/$regex/,@ioscan);
        my $vdisk_str = join(",",@vdisk);
        ($vdisk_str)=split(",",$vdisk_str);
        $vdisk_str=~s#\s+/dev/rdsk/.+##g;
        $vdisk_str=~s/\s//g;
        $vm_data{$vm}->{$_}->{"vdisk"}=$vdisk_str;
    }
}

# Debuging purpose
#print Dumper(\%vm_data);

foreach $vm (@vms) {
    printf("VM\tPhys\t\t\tVirt\n");

    foreach( keys(%{$vm_data{$vm}}) ) {
        printf("%s\t%s\t%s\n",$vm,$_,$vm_data{$vm}->{$_}->{"vdisk"});

    }
}
