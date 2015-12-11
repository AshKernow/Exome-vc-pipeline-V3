#!/bin/bash

# This script takes fastq files and aligns them with BWA mem
# The primary input is a TAB-delimited table containing the path to the fastq file and the RG read header for the output SAM file.
#   - Columns should be as follows:
#       For single end - <fastq files> <readgroup headers>
#       For paired end - <Read 1 fastq files> <readgroup headers> <Read 2 fastq files>
# The script will infer paired/single end from the number of columns in the table
#   e.g.:
#    Samp1_GATCAG_R1.fastq.gz    @RG\tID:Samp1_GATCAG\tSM:Samp1\tLB:Lib245\tPL:ILLUMINA\tCN:BISRColumbia    Samp1_GATCAG_R2.fastq.gz
#    Samp2_CAGTGC_R1_L001.fastq.gz    @RG\tID:Samp2_CAGTGC_L001\tSM:Samp2\tLB:Lib245\tPL:ILLUMINA\tCN:BISRColumbia    Samp2_CAGTGC_R2_L001.fastq.gz
#    Samp2_CAGTGC_R1_L002.fastq.gz    @RG\tID:Samp2_CAGTGC_L002\tSM:Samp2\tLB:Lib245\tPL:ILLUMINA\tCN:BISRColumbia    Samp2_CAGTGC_R2_L002.fastq.gz
#    Samp3_ATTGTC_R1.fastq.gz    @RG\tID:Samp3_ATTGTC\tSM:Samp3\tLB:Lib268\tPL:ILLUMINA\tCN:BISRColumbia    Samp3_ATTGTC_R2.fastq.gz

# The script will use the ID field of the RG header as the output file name
# If the table contains multiple lines run the script as an array job, each job will read the line from the table corresponding to its $SGE_TASK_ID
#    InpFil - (required) - Table defining input fastq files
#    RefFil - (required) - shell file containing variables with locations of reference files and resource directories; see list below for required variables
#    LogFil - (optional) - File for logging progress
#    TgtBed - (optional) - Exome capture kit targets bed file (must end .bed for GATK compatability) ; may be specified using a code corresponding to a variable in the RefFil giving the path to the target file- only required if calling pipeline
#    PipeLine - P -(flag) - will start the GATK realign and recalibrate pipeline using the files generated by this script
#    Flag - F - Fix mis-encoded base quality scores - Rewrite the qulaity scores from Illumina 1.5+ to Illumina 1.8+, will subtract 31 from all quality scores; used to fix encoding in some datasets (especially older Illumina ones) which starts at Q64 (see https://en.wikipedia.org/wiki/FASTQ_format#Encoding)
#    Help - H - (flag) - get usage information

#list of variables required in reference file:
# $REF - reference genome in fasta format - must have been indexed using 'bwa index ref.fa'
# $EXOMPPLN - directory containing exome analysis pipeline scripts, 

#list of required tools:
# samtools <http://samtools.sourceforge.net/> <http://sourceforge.net/projects/samtools/files/>
# bwa mem <http://bio-bwa.sourceforge.net/> <http://sourceforge.net/projects/bio-bwa/files/>
# java <http://www.oracle.com/technetwork/java/javase/overview/index.html>
# picard <http://picard.sourceforge.net/> <http://sourceforge.net/projects/picard/files/>

## This file also requires exome.lib.sh - which contains various functions used throughout the Exome analysis scripts; this file should be in the same directory as this script
###############################################################

#set default arguments
usage="
-t 1-{number of fastq files] ExmAln.1a.Align_Fastq_to_Bam_with_BWAmem.sh -i <InputFile> -a <line_number> -r <reference_file> -t <target intervals file> -l <logfile> -PH

     -i (required) - Table containing the path to the fastq file and the RG read header
     -a (optional) - The line number of the input file to process. default=1.
     -r (required) - shell file containing variables with locations of reference files and resource directories (WES_Pipeline_References.b37.sh)
     -l (optional) - Log file
     -t (optional) - Exome capture kit targets or other genomic intervals bed file (must end .bed for GATK compatability); this file is required if calling the pipeline but otherwise can be omitted
     -P (flag) - Initiate exome analysis pipeline after completion of script
     -F (flag) - Fix mis-encoded base quality scores - Rewrite the qulaity scores from Illumina 1.5+ to Illumina 1.8+
     -H (flag) - echo this message and exit
"

PipeLine="false"
ArrNum=1
#get arguments
while getopts i:a:r:l:t:PFH opt; do
    case "$opt" in
        i) InpFil="$OPTARG";;
        a) ArrNum="$OPTARG";;
        r) RefFil="$OPTARG";; 
        l) LogFil="$OPTARG";;
        t) TgtBed="$OPTARG";; 
        P) PipeLine="true";;
        F) FixMisencoded="true";;
        H) echo "$usage"; exit;;
    esac
done

#check all required paramaters present
if [[ ! -e "$InpFil" ]] || [[ ! -e "$RefFil" ]]; then echo "Missing/Incorrect required arguments"; echo "$usage"; exit; fi

#Call the RefFil to load variables
RefFil=`readlink -f $RefFil`
source $RefFil 

#Load script library
source $EXOMPPLN/exome.lib.sh #library functions begin "func"

#set local variables
InpFil=`readlink -f $InpFil`  # resolve input file path
NCOL=$(head -n1 $InpFil | wc -w | cut -d" " -f1) #get number of columns in file to determine SE or PE
fastq1=`readlink -f $(tail -n+$ArrNum $InpFil | head -n 1 | cut -f1)` #R1 or SE fastq from first column
if [ $NCOL -eq 3 ]; then
    fastq2=`readlink -f $(tail -n+$ArrNum $InpFil | head -n 1 | cut -f3)` #R2 fastq from third column if present
else
    fastq2=""
fi
rgheader=$(tail -n+$ArrNum $InpFil | head -n 1 | cut -f2) #RG header from second column
BamNam=$(basename $fastq1 | sed s/_R1// | sed s/.fq.gz// | sed s/.fastq.gz//) # a name for the output files - basically the original file name
if [[ -z "$LogFil" ]]; then LogFil=$BamNam.FqB.log; fi # a name for the log file
AlnDir=wd.$BamNam.align; mkdir -p $AlnDir; cd $AlnDir # create working and move into a working directory
AlnFil=$BamNam.bwamem.bam #filename for bwa-mem aligned file
SrtFil=$BamNam.bwamem.sorted.bam #output file for sorted bam
DdpFil=$BamNam.bwamem.mkdup.bam #output file with PCR duplicates marked
FlgStat=$BamNam.bwamem.flagstat #output file for bam flag stats
IdxStat=$BamNam.idxstats #output file for bam index stats
TmpLog=$BamNam.FqB.temp.log #temporary log file
TmpDir=$BamNam.FqB.tempdir; mkdir -p $TmpDir #temporary directory

#start log
ProcessName="Align with BWA"
funcWriteStartLog
echo " Build of reference files: "$BUILD >> $TmpLog
echo "----------------------------------------------------------------" >> $TmpLog

###Align using BWA mem algorithm
# align with BWA-mem | transform sam back to bam
StepName="Align with BWA mem"
StepCmd="bwa mem -M -t 6 -R \"$rgheader\" $REF $fastq1 $fastq2 |
 samtools view -b - > $AlnFil"
if [[ $FixMisencoded == "true" ]]; then 
 StepCmd="bwa mem -M -t 6 -R \"$rgheader\" $REF $fastq1 $fastq2 |
 seqtk seq -Q64 -V - |
 samtools view -b - > $AlnFil"
fi
funcRunStep

#Sort the bam file by coordinate
StepName="Sort Bam using PICARD"
StepCmd="java -Xmx4G -XX:ParallelGCThreads=1 -Djava.io.tmpdir=$TmpDir -jar $PICARD SortSam
 INPUT=$AlnFil
 OUTPUT=$SrtFil
 SORT_ORDER=coordinate
 CREATE_INDEX=TRUE"
funcRunStep
rm $AlnFil #remove the "Aligned bam"

#Mark the duplicates
StepName="Mark PCR Duplicates using PICARD"
StepCmd="java -Xmx4G -XX:ParallelGCThreads=1 -Djava.io.tmpdir=$TmpDir -jar $PICARD MarkDuplicates
 INPUT=$SrtFil
 OUTPUT=$DdpFil
 METRICS_FILE=$DdpFil.dup.metrics.txt
 CREATE_INDEX=TRUE"
funcRunStep
rm $SrtFil ${SrtFil/bam/bai} #remove the "Sorted bam"

#Call next steps of pipeline if requested
NextJob="Run Genotype VCF"
NextCmd="$EXOMPPLN/ExmAln.2.HaplotypeCaller_GVCFmode.sh -i $DdpFil -r $RefFil -t $TgtBed -l $LogFil -B"
funcPipeLine
#Always do the BAM stats
PipeLine="true"
NextJob="Get basic bam metrics"
NextCmd="$EXOMPPLN/ExmAln.3a.Bam_metrics.sh -i $DdpFil -r $RefFil -l $LogFil"
funcPipeLine
funcPipeLineNextJob="Run Depth of Coverage"
NextCmd='$EXOMPPLN/ExmAln.8a.DepthofCoverage.sh -i $DdpFil -r $RefFil -t $TgtBed -l $LogFil -B > DoC.$BamNam.$$.o 2>&1'
funcPipeLine

#Get flagstat
StepName="Output flag stats using Samtools"
StepCmd="samtools flagstat $DdpFil > $FlgStat"
funcRunStep

#get index stats
StepName="Output idx stats using Samtools"
StepCmd="samtools idxstats $DdpFil > $IdxStat"
funcRunStep


#End Log
funcWriteEndLog
