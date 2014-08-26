#!/bin/bash
#
# Script to generate whole genome GC3 plots (specifically desinged for fungus size genomes)
# User needs to supply a GFF file (GFF3/GTF/BED) and assembled genome (FASTA)
# Plots the moving average of GC3 content for genes for each chromosome in the same order they appear
#
# Needs BEDTools installed (uses module on Lightning3)
#
#
# Plotting is perfomed after filtering:
# 1. GC3 are plotted for CDS sequences only
# 2. Length of the gene should be greater than 300 bases
# 3. Length is a multiple of three
#
#
# Arun Seetharam <arnstrm@iastate.edu>, Genome Informatics Faciltiy
# 26 August, 2014
#
#

if [ $# -lt 2 ] ; then
echo "Genome_GC3_plots.sh <gff> <fasta>"
exit 0
fi
# Read files
GFF="$1"
FASTA="$2"
# create basename for naming files
GBASE=$(basename ${GFF%.*})
# load modules
module use /data004/software/GIF/modules
module load bedtools
# CodonW executable
CODW="/data004/software/GIF/packages/codonW/1.4.4"

# extract only CDS regions from GFF3 file
awk '$3=="CDS" {print $0}' ${GFF} > ${GBASE}_CDS.gff
# extract FASTA sequences form the Genome
bedtools getfasta -fi ${FASTA} -bed ${GBASE}_CDS.gff -fo ${GBASE}_CDS.fasta
# calculate GC3 for all genes
${CODW}/codonw ${GBASE}_CDS.fasta ${GBASE}_GC3.txt ${GBASE}_GC3.blk -nomenu -nowarn -noblk -gc3s
# Filter Genes and sort them based on co-ordinates
sed -i -e 's/ //g' -e 's/:/\t/g' -e 's/-/\t/g' ${GBASE}_GC3.txt
awk '{print $0, $3-$2+1}' ${GBASE}_GC3.txt | awk '($NF % 3) == 0' | awk '$NF >= 300' > ${GBASE}_filtered.txt

# separate them to chromosomes and generate a R script for plotting
for chr in $(cut -f 1 ${GBASE}_filtered.txt |sort | uniq); do
  grep -w "${chr}" ${GBASE}_filtered.txt | sort -k 3,3 -n | awk '{print NR"\t"$4*100}'> ${GBASE}_${chr}.txt
  sed -i '1 i Order\tChr'${chr}'' ${GBASE}_${chr}.txt
  lines=$(wc -l ${GBASE}_${chr}.txt | cut -d " " -f 1);
# check if the files have enough CDS's to plot
  if [ "${lines}" -gt "20" ]; then
# here-docs for R plot
  cat <<CMD1 >> rplots_pdf.R
dv <- read.table("${GBASE}_${chr}.txt", header=1)
gc3pc = dv[,2]
coef15 = 1/15
ma15 = filter(gc3pc, rep(coef15, 15), sides=1)
jpeg("${GBASE}_Chr${chr}.jpg", width=5, height=5, units="in", res=500)
plot(gc3pc, type="l", main="Chromosome ${chr}", xlab="Gene number", ylab="GC3 %", col="white")
lines(ma15, col="black")
dev.off()
CMD1
else
  echo "#skipping Chr${chr}"
fi
done
# Run R script
Rscript rplots_pdf.R;
# save plots in another directory
mkdir -p ${GBASE}_plots
mv *.jpg ${GBASE}_plots/
