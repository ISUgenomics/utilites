#!/bin/bash
# This script splits the large input fasta file and BLASTs them in parallel.
# specifically, for the Stampede HPC cluster
#
# Arun Seetharam <arnstrm@iastate.edu>, Genome Informatics Faciltiy
# 19 August, 2014

scriptName="${0##*/}"
function printUsage() {
    cat <<EOF

Synopsis

    $scriptName [-h | --help] -s splits path/to/fasta_file.fasta path/to/blast/database_name

Description

    This script splits the large input fasta file and BLASTs them in parallel, specifcally for the Stampede cluster
    
	-s, --splits=N
        generate N number of splits to run the BLAST. Since each node has 16 processors in Stampede,
        it is preferable to have splits as multiple of 16.		

    -b, --blast-parameters=STRING
        The BLAST type and parameters required for carrying out BLAST search. By default, "blastp -outfmt 6"	
		will be used. Note that you don't have to specify '-db' AND '-query' options here
		
	path/to/fasta_file.fasta
        full path to the FASTA file for using as BLAST query
        script assumes the files have *.fasta extension

    path/to/blast/database_name
        full path to the BLAST database name (generated from ncbi makeblastdb)
		Make sure that the path is absoulute

    -h, --help
        Brings up this help page

Author

    Arun Seetharam, Genome Informatics Facilty, Iowa State University
    arnstrm@iastate.edu
    19 August, 2014

EOF
}
blastparameters="blastp -max_target_seqs 1 -outfmt 6"

if [ $# -lt 1 ] ; then
    printUsage
    echo -e "Please specify the splits, fasta file and database path for processing\n\n"
	exit 1
fi
while :
do
    case $1 in
        -h | --help | -\?)
            printUsage
            exit 0
            ;;
        -s | --splits)
            splits=$1
            shift 1
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf >&2 'WARNING: Unknown option (ignored): %s\n' "$1"
            shift
            ;;
        *)
            break
            ;;
    esac
done
infile="$1"
blastDB="$2"

inbase=$(basename "${infile%.*}")
cat <<JOBHEAD > parallel_blast.sub
#!/bin/bash
#SBATCH -J blast_${inbase}
#SBATCH -o blast_${inbase}.o%j
#SBATCH -e blast_${inbase}.e%j
#SBATCH -n ${splits}
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
  parallel --jobs ${splits} --block 100k --recstart '>' --pipe \
  ${blastparameters} \
  -db ${blastDB} -query - \
  > ${inbase}_results.txt
JOBHEAD

sbatch parallel_blast.sub
