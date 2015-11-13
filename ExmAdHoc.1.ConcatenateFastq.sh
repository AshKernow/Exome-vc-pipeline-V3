#!/bin/bash
#$ -l mem=4G,time=4:: -N CatFastq -S /bin/bash -cwd 

# This script concatenates fastq.gz files into a single file using zcat
# The main input it is directory containing fastq files
# All fastq's in the directory will be combined into 1 (single end) or 2 (paired end) files, so the directory should contain fastqs for only 1 sample/readgroup
# It is necessary to specifiy "SE" for single end or "PE" for paired end
# If using PE then call the job as an array job using "qsub -t 1-2 ...."
# If paired end, the files for paired ends should be marked with one of the following: "_R1_" & "_R2_"; ".R1." & ".R2.";"_R1." & "_R2"; "_R1." & "_R2."
# Generally file names should be in the format such as <SAMPLENAMELANEETCETC>_R<PAIRNUMBER>_<Section_NUMBER>.fastq.gz
#    FqDir - (required) - A directory containing fastq files
#    Type - (required) - "PE" for paired end, "SE" for single end
#    OutNam - (optional) - A name for the output file. If this is not provided it will be derived from the directory name.
#    Help - H - (flag) - get usage information

#Required Variable:
EXOMPPLN="/home/local/ARCS/ads2202/scripts/ExomePipelineScripts"

#list of required tools:
# standard linux library


## This file also requires exome.lib.sh - which contains various functions used throughout the Exome analysis scripts; this file should be in the same directory as this script

###############################################################

usage="
<-t 1-2>* ExmAdHoc.1.ConcatenateFastq.sh -i <InputDirectory> -t <Type> -r <READ> -o <OutputName>
*NOTE: If using PE then call the job as an array job using \"-t 1-2\"

     -i (required) - Path to directory containing fastq.gz files
     -t (required) - \"PE\" for paired-end \"SE\" for single-end
     -r (optional) - R1 or R2 - for paired-end, specifies which group of files to concatenate - there is no need to specify this, the PE option will call two new jobs
     -o (optional) - Output filename - if not provided the directory name will be used
     -H (flag) - echo this message and exit
"

#get arguments
while getopts i:t:o:r:H opt; do
    case "$opt" in
        i) FqDir="$OPTARG";;
        t) Type="$OPTARG";; 
        o) OutNam="$OPTARG";;
        r) ReadEnd="$OPTARG";;
        H) echo "$usage"; exit;;
    esac
done

#Load script library
source $EXOMPPLN/exome.lib.sh #library functions begin "func" #library functions begin "func"

#check directory exists
if [[ ! -d $FqDir ]]; then
    echo  "Need provide a directory"
    echo $usage
    exit
fi

#check for PE/SE specification
if [[ "$Type" != "PE" ]] && [[ "$Type" != "SE" ]]; then
    echo  "Need to specify paired-end or single-end"
    echo $usage
    exit
fi

if [[ -z "$OutNam" ]]; then OutNam=$FqDir; fi #Set output file name if not provided

echo $ReadEnd
if [[ "$Type" == "SE" ]]; then
    echo "Single End"
    #If single end concatenate all fastq
    FqFils=$(find $FqDir | grep "fastq.gz" | uniq | sort)
    echo "----Fastq List---"
    echo "$FqFils"
    zcat $FqFils | gzip > $OutNam".fastq.gz"
    echo "Done"
elif [[ "$Type" == "PE" ]] && [[ "$ReadEnd" == "R1" ]]; then
    echo "Paired End - Read 1"
    FqFils=$(find $FqDir | grep -E "[_.]R1[_.]" | grep "fastq.gz" | uniq | sort)
    echo "----Fastq List R1 ---"
    echo "$FqFils"
    zcat $FqFils | gzip > $OutNam"_R1.fastq.gz"
    echo "Done R1"
elif [[ "$Type" == "PE" ]] && [[ "$ReadEnd" == "R2" ]]; then
    echo "Paired End - Read 2"
    FqFils=$(find $FqDir | grep -E "[_.]R2[_.]" | grep "fastq.gz" | uniq | sort)
    echo "----Fastq List R2 ---"
    echo "$FqFils"
    zcat $FqFils | gzip > $OutNam"_R2.fastq.gz"
    echo "Done R2"
elif [[ "$Type" == "PE" ]] && [[ ! $ReadEnd ]]; then
    ThisScript=`readlink -f $0`
    echo "Paired End - sending new jobs"
    nohup $ThisScript -i $FqDir -t "PE" -o $OutNam -r "R1" > Concate$OutNam.R1.o 2> Concate$OutNam.R1.e &
    nohup $ThisScript -i $FqDir -t "PE" -o $OutNam -r "R2" > Concate$OutNam.R2.o 2> Concate$OutNam.R2.e &
fi
