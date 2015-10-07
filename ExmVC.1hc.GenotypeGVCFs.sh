#!/bin/bash

# This script takes a list of gVCF files generated by the HaplotypeCaller (filename must end ".list") and performs the multi-sample joint aggregation step. This job would generally be used in a scatter-gather parellisation as the HC is very computationally intensive. The ArrNum parameter facilitates this.
#    InpFil - (required) - List of gVCF files. List file name must end ".list"
#    RefFil - (required) - shell file containing variables with locations of reference files, jar files, and resource directories; see list below for required variables
#    TgtBed - (optional) - Exome capture kit targets bed file (must end .bed for GATK compatability) ; may be specified using a code corresponding to a variable in the RefFil giving the path to the target file- only required if calling pipeline
#    VcfNam - (optional) - A name for the analysis - to be used for naming output files. Will be derived from input filename if not provided
#    ArrNum - (optional) - If the job is part of a scatter-gather array, this is appended to all outputs to that they can be differentiated from outputs from other jobs in the array. (i.e. if the VCF is to be called MyData, then each array element outputs MyData.01.vcf, Mydata.02.vcf ... MyData.0n.vcf).
#    LogFil - (optional) - File for logging progress
#    Flag - P - PipeLine - call the next step in the pipeline at the end of the job
#    Flag - B - BadET - prevent GATK from phoning home
#    Help - H - (flag) - get usage information

#list of required vairables in reference file:
# $REF - reference genome in fasta format - must have been indexed using 'bwa index ref.fa'
# $DBSNP - dbSNP vcf from GATK
# $EXOMPPLN - directory containing exome analysis pipeline scripts
# $GATK - GATK jar file 
# $ETKEY - GATK key file for switching off the phone home feature, only needed if using the B flag

#list of required tools:
# java <http://www.oracle.com/technetwork/java/javase/overview/index.html>
# GATK <https://www.broadinstitute.org/gatk/> <https://www.broadinstitute.org/gatk/download>

## This file also requires exome.lib.sh - which contains various functions used throughout the Exome analysis scripts; this file should be in the same directory as this script

###############################################################

#set default arguments
usage="
ExmVC.1hc.GenotypeGVCFs.sh -i <InputFile> -r <reference_file> -t <targetfile> -l <logfile> -PABH

     -i (required) - List of gVCF files. List file name must end \".list\"
     -r (required) - shell file containing variables with locations of reference files and resource directories
     -t (required) - Exome capture kit targets or other genomic intervals bed file (must end .bed for GATK compatability)
     -n (optional) - Analysis/output VCF name - will be derived from input filename if not provided; only used if calling pipeline
     -l (optional) - Log file
     -a (optional) - Array number, if the job is part of a scatter-gather parallelisation array
     -P (flag) - Call next step of exome analysis pipeline after completion of script
     -X (flag) - Do not run Variant Quality Score Recalibration - only if calling pipeline
     -B (flag) - Prevent GATK from phoning home
     -H (flag) - echo this message and exit
"

AllowMisencoded="false"
PipeLine="false"
NoRecal="false"
BadET="false"

while getopts i:r:t:n:l:a:PXBH opt; do
    case "$opt" in
        i) InpFil="$OPTARG";;
        r) RefFil="$OPTARG";;
        t) TgtBed="$OPTARG";;
        n) VcfNam="$OPTARG";;
        l) LogFil="$OPTARG";;
        a) ArrNum="$OPTARG";;
        P) PipeLine="true";;
        X) NoRecal="true";;
        B) BadET="true";;
        H) echo "$usage"; exit;;
  esac
done

#check all required paramaters present
if [[ ! -e "$InpFil" ]] || [[ ! -e "$RefFil" ]] || [[ -z "$TgtBed" ]]; then
 echo "Missing/Incorrect required arguments"
 echo "provided arguments: -i $InpFil -r $RefFil -t $TgtBed"
 echo "usage: $usage"
 exit
fi

#Call the RefFil to load variables
RefFil=`readlink -f $RefFil`
source $RefFil

#Load script library
source $EXOMPPLN/exome.lib.sh #library functions begin "func" #library functions begin "func"


#Set local Variables
if [[ -z "$VcfNam" ]];then VcfNam=`basename $InpFil`; VcfNam=${VcfNam/.list/}; fi # a name for the output files
if [[ -z $LogFil ]]; then LogFil=$VcfNam.GgVCF.log; fi # a name for the log file
VcfDir=$VcfNam.splitfiles; mkdir -p $VcfDir # Directory to output slices to
PrgDir=$VcfNam.progfiles; mkdir -p $PrgDir # "Progress directory" to output completion logs to, these are used by the merge script to check that all jobs in this array have finished (if jobs run out of time the hold is released even if the jobs did not complete)
if [[ $ArrNum ]]; then VcfNam=$VcfNam.$ArrNum; fi
PrgFil=$VcfNam.genotypingcomplete
VcfFil=$VcfDir/$VcfNam.vcf #Output File
VcfAnnFil=$VcfDir/$VcfNam.ann.vcf
VcfLeftAlnFil=$VcfDir/$VcfNam.LA.vcf
GatkLog=$VcfNam.GgVCF.gatklog #a log for GATK to output to, this is then trimmed and added to the script log
TmpLog=$VcfNam.GgVCF.temp.log #temporary log file
TmpDir=$VcfNam.GgVCF.tempdir; mkdir -p $TmpDir #temporary directory
infofields="-A AlleleBalance -A BaseQualityRankSumTest -A Coverage -A MappingQualityRankSumTest -A MappingQualityZero -A QualByDepth -A RMSMappingQuality -A FisherStrand -A InbreedingCoeff -A QualByDepth -A ChromosomeCounts -A GenotypeSummaries -A StrandOddsRatio -A DepthPerSampleHC"
# -A HomopolymerRun
# -A SpanningDeletions 

#Start Log File
ProcessName="Joint calling of gVCFs with GATK GenotypeGVCFs" # Description of the script - used in log
funcWriteStartLog

##Run Joint Variant Calling
StepName="Joint call gVCFs with GATK"
StepCmd="java -Xmx20G -Djava.io.tmpdir=$TmpDir -jar $GATKJAR
 -T GenotypeGVCFs
 -R $REF
 -L $TgtBed
 --interval_padding 100
 -V $InpFil
 -o $VcfFil
 -D $DBSNP
 $infofields
 -log $GatkLog" #command to be run
funcGatkAddArguments # Adds additional parameters to the GATK command depending on flags (e.g. -B or -F)
funcRunStep

##Annotate VCF with GATK
infofields="-A AlleleBalance -A BaseQualityRankSumTest -A Coverage -A HaplotypeScore -A HomopolymerRun -A MappingQualityRankSumTest -A MappingQualityZero -A QualByDepth -A RMSMappingQuality -A SpanningDeletions -A FisherStrand -A InbreedingCoeff -A ClippingRankSumTest -A DepthPerSampleHC -A ChromosomeCounts -A GenotypeSummaries -A StrandOddsRatio"
StepName="Joint call gVCFs"
StepCmd="java -Xmx7G -Djava.io.tmpdir=$TmpDir -jar $GATKJAR
 -T VariantAnnotator 
 -R $REF
 -L $VcfFil
 -V $VcfFil
 -o $VcfAnnFil
 -D $DBSNP
  $infofields
 -log $GatkLog" #command to be run
funcGatkAddArguments # Adds additional parameters to the GATK command depending on flags (e.g. -B or -F)
funcRunStep
mv -f $VcfAnnFil $VcfFil
mv -f $VcfAnnFil.idx $VcfFil.idx

##Left Align variants
StepName="Left align variants in the VCF with GATK"
StepCmd="java -Xmx4G -Djava.io.tmpdir=$TmpDir -jar $GATKJAR
 -T LeftAlignAndTrimVariants
 -R $REF
 -V $VcfFil
 -o $VcfLeftAlnFil
 -log $GatkLog" #command to be run
funcGatkAddArguments # Adds additional parameters to the GATK command depending on flags (e.g. -B or -F)
funcRunStep
mv -f $VcfLeftAlnFil $VcfFil
mv -f $VcfLeftAlnFil.idx $VcfFil.idx


##Write completion log
touch $PrgDir/$PrgFil

#End Log
funcWriteEndLog
