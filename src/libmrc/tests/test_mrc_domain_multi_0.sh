#! /bin/sh

set -e

openmpirun -n 1 ./test_mrc_domain_multi --mrc_io_type xdmf2

TEST=0
for a in reference_results/$TEST/*.xdmf; do 
    b=`basename $a`
    cmp $b $a
done

for a in reference_results/$TEST/*.h5.dump; do 
    b=`basename $a .dump`
    h5dump $b > $b.dump
    cmp $b.dump $a
    rm $b.dump
done

