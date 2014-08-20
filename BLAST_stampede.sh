#!/bin/bash
# This script splits the large input fasta file and BLASTs them in parallel.
# specifically, for the Stampede HPC cluster
#
# Change the BLAST parameters to adjust your needs
blastparameters="blastp -max_target_seqs 1 -outfmt 6"
#
# NOTE: EXCLUDE '-db' AND '-query' OPTIONS
# You may also need to change the user email address and account number below
#
# Arun Seetharam <arnstrm@iastate.edu>, Genome Informatics Faciltiy
# 19 August, 2014

if [ $# -lt 3 ] ; then
echo "BLASTstampede.sh <number of splits> <fasta file> <full path for blast database>"
exit 0
fi

splits="$1"
infile="$2"
blastDB="$3"

fsize=$(du -k "$infile" | cut -f 1)
bsize=$(echo "scale=0; (${fsize} / ${splits})" | bc)
inbase=$(echo "${infile%.*}")

cat <<JOBHEAD > parallel_blast.sub
#!/bin/bash
#SBATCH -J blast_${inbase}
#SBATCH -o blast_${inbase}.o%j
#SBATCH -e blast_${inbase}.e%j
#SBATCH -n ${splits}
#SBATCH -c 1
#SBATCH -p normal
#SBATCH -t 48:00:00
#SBATCH --mail-user=arnstrm@gmail.com
#SBATCH --mail-type=begin
#SBATCH --mail-type=end
#SBATCH -A TG-MCB140103
module load blast
module use /home1/02929/arnstrm/programs/modules
module load parallel
cat ${infile} | \
  parallel --block ${bsize}k --recstart '>' --pipe \
  ${blastparameters} \
  -db ${blastDB} -query - \
  >> ${inbase}_results.txt
JOBHEAD

sbatch parallel_blast.sub
