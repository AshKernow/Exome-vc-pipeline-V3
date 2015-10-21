#Library of functions used throughout Exome analysis scriptd

#-------------------------------------------------------------------------------------------------------
#Function to set the target file location when given a code present as a variable in the reference file
funcGetTargetFile (){
    if [[ "$TGTCODES" == *"$TgtBed"* ]];then
        eval TgtBed=\$$TgtBed
    fi
}
#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
#Function to get input file name from a list of files in an array job
funcFilfromList() {
ChecList=${InpFil##*.}
if [[ "$ChecList" == "list" ]];then
    echo $ChecList
    InpFil=$(head -n $ArrNum $InpFil | tail -n 1)
fi
}
#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
#Function to enter information about the script initiation into the log
funcWriteStartLog () {
uname -a >> $TmpLog
echo "Start "$0" - $0:`date`" >> $TmpLog
echo " Input File: "$InpFil >> $TmpLog
if [[ -n "$BamFil" ]]; then echo " Bam File: "$BamFil >> $TmpLog; fi
if [[ -n "$BamNam" ]]; then echo " Base name for outputs: $BamNam" >> $TmpLog; fi
if [[ -n "$VcfFil" ]]; then echo " Vcf File: "$VcfFil >> $TmpLog; fi
if [[ -n "$VcfNam" ]]; then echo " Base name for outputs: $VcfNam" >> $TmpLog; fi
if [[ -n "$Chr" ]]; then echo " Chromosome: "$Chr >> $TmpLog; fi
if [[ -n "$TgtBed" ]]; then echo " Target Intervals File: "$TgtBed >> $TmpLog; fi
if [[ -n "$RefFil" ]]; then echo " Pipeline Reference File: "$RefFil >> $TmpLog; fi
echo "----------------------------------------------------------------" >> $TmpLog
}
#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
#function to log the start of each step wtihin a script
funcLogStepStart () { echo "- Start $StepName `date`...">> $TmpLog ; } 
#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
#function checks that the step has completed successfully, if not it writes and error message to the log and exits the script, otherwise it logs the completion of the step
funcLogStepFinit () { 
if [[ $? -ne 0 ]]; then #check exit status and if error then...
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" >> $TmpLog
    echo "     $StepName failed `date`" >> $TmpLog
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" >> $TmpLog
    echo "=================================================================" >> $TmpLog
    if [[ $StepCmd == *GenomeAnalysisTK.jar* ]]; then mv $GatkLog GATK_Error_Log_$StepName"_"$GatkLog; fi
    cat $TmpLog >> $LogFil
    rm $TmpLog
    exit 1
elif [[ $StepCmd == *GenomeAnalysisTK.jar* ]]; then 
    tail -n 1 $GatkLog >> $TmpLog
    rm $GatkLog
fi
echo "- End $StepName `date`...">> $TmpLog # if no error log the completion of the step
echo "-----------------------------------------------------------------------" >> $TmpLog
}
#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
#function to run and log the initiation/completion/failure of each step in the script
funcRunStep (){
funcLogStepStart
if [[ `type -t "$StepCmd"` ]]; then 
    type $StepCmd | tail -n +3  >> $TmpLog
else
    echo $StepCmd >> $TmpLog
fi
eval $StepCmd
funcLogStepFinit
}
#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
#function to log the end of each script and transfer the contents of temporary log file to the main log file
funcWriteEndLog () {
echo "End "$0" $0:`date`" >> $TmpLog
echo "===========================================================================================" >> $TmpLog
echo "" >> $TmpLog
cat $TmpLog >> $LogFil
rm -r $TmpLog $TmpDir
}
#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
# function for common additional arguments to GATK
funcGatkAddArguments (){
if [[ "$AllowMisencoded" == "true" ]]; then StepCmd=$StepCmd" -allowPotentiallyMisencodedQuals"; fi
if [[ "$FixMisencoded" == "true" ]]; then StepCmd=$StepCmd" -fixMisencodedQuals"; fi
if [[ "$BadCigar" == "true" ]]; then StepCmd=$StepCmd" -rf BadCigar"; fi
if [[ "$BadET" == "true" ]]; then StepCmd=$StepCmd" -et NO_ET -K $ETKEY"; fi
}

#-------------------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------------------
# function for calling next step in pipeline
funcPipeLine (){
if [[ "$PipeLine" == "true" ]]; then
    echo "- Call $NextJob `date`:" >> $TmpLog
    echo "    "$NextCmd  >> $TmpLog
    NextCmd="nohup "$NextCmd" &"
    eval $NextCmd >> $TmpLog
    echo "----------------------------------------------------------------" >> $TmpLog
else
    echo "- To start $NextJob run the following command:" >> $TmpLog
    echo "    "$NextCmd  >> $TmpLog
    echo "----------------------------------------------------------------" >> $TmpLog
fi
}
#-------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------
