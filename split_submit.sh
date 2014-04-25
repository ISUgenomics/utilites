#!/bin/bash
#
# PacBio is configured based on this blog: http://www.homolog.us/blogs/blog/2013/02/05/pacbiotoca-for-error-correcting-pacbio-reads
#
#
# Arun Seetharam <arnstrm@iastate.edu>, Genome Informatics Faciltiy
# 23 April, 2014

scriptName="${0##*/}"
function printUsage() {
    cat <<EOF

Synopsis

    $scriptName [-h | --help] -l line -s splits path/to/pacbio_fastq path/to/illumina_frg_file

Description

    This scripts breaks the pacbio subreads FASTQ files into usersupplied number of peices and submits for error correction
    Job script is degined to use ISU Lightning 3 cluster, scpecifically long_1node queue (1 node, 32 procs with 256Gb RAM).
    Make sure you create a softlink for the original FASTQ file (pacbio) and run it in a separate directory.
    Error corrected output will be named as ec_NNNNNN.fastq, where NNNNNN is the time stamp obtained form the input filename.

	-l, --line=line_name
        line name to be used to identify the files. Any name can be specified (of any length). 
        Generally a 1-4 letter suffix for identification purpose is suffecient.

	-s, --splits=N
        generate N number of splits to run the error correction. Generally, if the number of FASTQ reads is < 35K,
        it finishes within 20 hrs (with aproximately 200M Illumina reads)		

	path/to/pacbio_fastq
        full path to the FASTQ files (generated from PacBio bas.h5 files) for error correction
        script assumes the files have *.fastq extension and is softlinked (DO NOT RUN ON ORIGINAL FILE)

    path/to/illumina_frg_file
        full path to the FRG file (generated from Illumina FASTQ files)

    -h, --help
        Brings up this help page

Author

    Arun Seetharam, Genome Informatics Facilty, Iowa State University
    arnstrm@iastate.edu
    23 April, 2014


EOF
}
if [ $# -lt 1 ] ; then
    printUsage
    echo -e "Please specify the ID, splits, fastq file and frg file for processing\n\n"
	exit 1
fi
while :
do
    case $1 in
        -h | --help | -\?)
            printUsage
            exit 0
            ;;
        -l | --line)
            LINE=$2
            shift 2
            ;;
        -s | --splits)
            NSPLIT=$2
            shift 2
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

#LINE="$1"
#NSPLIT="$2"
FILE="$1"
FRG="$2"
PRE=$(pwd)
BASE=$(echo ${FILE%%.*})

if ! [ -L ${FILE} ]; then
  echo "${FILE} is not a Sym Link file!"
  exit 1
fi

if ! [ -e ${FRG} ]; then
  echo "${FRG} doesn't exist!"
  exit 1
fi

cat > pacbio.spec << "PACSPEC"
utgErrorRate = 0.25
utgErrorLimit = 6.5
cnsErrorRate = 0.25
cgwErrorRate = 0.25
ovlErrorRate = 0.25
merSize=14
merylMemory = 128000
merylThreads = 16
ovlStoreMemory = 8192
useGrid = 0
scriptOnGrid = 0
frgCorrOnGrid = 0
ovlCorrOnGrid = 0
ovlHashBits = 24
ovlThreads = 2
ovlHashBlockLength = 20000000
ovlRefBlockSize =  50000000
frgCorrThreads = 2
frgCorrBatchSize = 100000
ovlCorrBatchSize = 100000
ovlConcurrency = 6
cnsConcurrency = 16
frgCorrConcurrency = 8
ovlCorrConcurrency = 16
cnsConcurrency = 16
PACSPEC

TOL=$(wc -l ${FILE} |cut -d " " -f 1)
NOL=$(echo "scale=0; (${TOL} / ${NSPLIT})" | bc)

while [ ! $(( ${NOL} % 4 )) -eq 0 ]
do
  NOL=$(( $NOL + 1 ))
done

split -d -l ${NOL} ${FILE} "${BASE}_"
unlink ${FILE}

shopt -s nullglob
SFILES=(${BASE}*)

for SFILE in ${SFILES[@]}; do
NUM=$(echo ${SFILE} | rev | cut -d "_" -f 1 | rev)
mkdir ${NUM};
mv ${SFILE} ./${NUM}/${SFILE}.fastq
IDN=$(echo ${SFILE} | cut -d "_" -f 2);
cat << SUBF > ${IDN}_${NUM}_${LINE}.sub
#!/bin/bash
#PBS -l vmem=256Gb,pmem=8Gb,mem=256Gb
#PBS -l nodes=1:ppn=32:ib
#PBS -l walltime=48:00:00
#PBS -N ${IDN}_${NUM}_${LINE}
#PBS -o \${PBS_JOBNAME}.o\${PBS_JOBID}
#PBS -e \${PBS_JOBNAME}.e\${PBS_JOBID}
cd \$PBS_O_WORKDIR
ulimit -s unlimited
echo "################ STATS ##################"
date +"%s"
SSECS=\$(date +"%s")
START=\$(date +"%r, %m-%d-%Y")
echo -e "Host\\t\\t: `hostname`"
echo -e "Processors\\t: \$(wc -l < \$PBS_NODEFILE)"
echo -e "Nodes\\t\\t: \$(uniq \$PBS_NODEFILE | wc -l)"
echo -e "Total memory\\t: \$(free | grep Mem | awk '{print \$2/1048576}' OFMT="%2.2f") Gb"
echo -e "Free memory\\t: \$(free | grep Mem | awk '{print \$4/1048576}' OFMT="%2.2f") Gb"
echo -e "Directory\\t: \$(pwd)"
chmod g+rw \${PBS_JOBNAME}.[eo]\${PBS_JOBID}
echo "#########################################"
module use /data004/software/GIF/modules
module load bowtie2
source /data004/software/GIF/packages/SMRT/2.2.0/install/smrtanalysis-2.2.0.133377/etc/setup.sh
pacBioToCA -l ec_${IDN}_${NUM}.fastq -t 32 -s ${PRE}/pacbio.spec -fastq ${SFILE}.fastq ${FRG}
echo "############# TIME STAMP ################"
DIFF=\$((\`date +"%s"\`-\${SSECS}))
echo -e "START\\t\\t: \${START}"
echo -e "END\\t\\t: \$(date +"%r, %m-%d-%Y")"
echo -e "TIME (hh:mm:ss)\\t: \`date -u -d \@\${DIFF} +"%T"\`"
echo "#########################################"
SUBF

mv ${IDN}_${NUM}_${LINE}.sub ./${NUM}/ ;
cd ${NUM}
echo "qsub ${IDN}_${NUM}_${LINE}.sub";
cd .. ;
done
