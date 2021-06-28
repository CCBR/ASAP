#########################################################
# INPUT FUNCTIONS FOR RULES
#########################################################

def get_replicate_tagAlignFiles_for_sample(wildcards):
    """
    Return list of tagAlign.gz files for each replicate for this sample
    tagAlign file is generated by align rule and is already Tn5 shifted
    These files are input for macs2 based peak calling
    """
    replicates=SAMPLE2REPLICATES[wildcards.sample]
    d=dict()
    for i,s in enumerate(replicates):
        d["tagAlign"+str(i+1)]=join(RESULTSDIR,"tagAlign",s+".tagAlign.gz")
    return d

#########################################################

def get_replicate_qsortedBamFiles_for_sample(wildcards):
    """
    Return list of query sorted bam files for each replicate for this sample
    bam file is generated by align rule and used for Genrich calling
    """
    replicates=SAMPLE2REPLICATES[wildcards.sample]
    d=dict()
    for i,s in enumerate(replicates):
        d["qsortedBam"+str(i+1)]=join(RESULTSDIR,"qsortedBam",s+".qsorted.bam")
    return d

#########################################################

def get_peakfiles_for_motif_enrichment(wildcards):
    """
    make a list of narrowPeak files for replicates and consensus.bed files for samples
    """
    replicates=SAMPLE2REPLICATES[wildcards.sample]
    d=dict()
    count=0
    for peakcaller in [ "macs2", "genrich" ]:
    # for peakcaller in wildcards.peakcaller:
        for replicate in replicates:
            narrowPeak=join(RESULTSDIR,"peaks",peakcaller,replicate+"."+peakcaller+".qfilter.narrowPeak")
            count+=1
            d[str(count)]=narrowPeak
        consensusBed=join(RESULTSDIR,"peaks",peakcaller,wildcards.sample+"."+peakcaller+".consensus.bed")
        count+=1
        d[str(count)]=consensusBed
    return d


#########################################################
#########################################################

rule atac_macs_peakcalling:
# """
# Calling ATACseq peaks using MACS2 
# This is based off of ENCODEs MACS2 peak calling for ATACseq data
# Input: Tn5 shifted TagAlign files for each sample (multiple replicates mean multiple tagalign files)
# Output:
# * MACS2 peaks per-replicate
# * qvalue-filtered MACS2 peaks per-replicate
# * consensus peaks and consensus-qvalue-filtered peaks per-sample
# * ChIPseeker annotations for peaks and filtered peaks (hg38/hg19/mm10/mm9 are currently supported)
# * Tn5 nicks in Bam (and Bed) format
# """
    input:
        unpack(get_replicate_tagAlignFiles_for_sample)
    params:
        genome=GENOME,
        genomefile=GENOMEFILE,
        outdir=join(RESULTSDIR,"peaks","macs2"),
        scriptsdir=SCRIPTSDIR,
        qcdir=QCDIR,
        script="ccbr_atac_macs2_peak_calling.bash",
        sample="{sample}",
        macs2_extsize=config["macs2"]["extsize"],
        macs2_shiftsize=config["macs2"]["shiftsize"],
        macs2_annotatePeaks=config["macs2"]["annotatePeaks"],
        macs2_effectiveGenomeSize=config[GENOME]["effectiveGenomeSize"]
    output:
        consensusPeakFileList=join(RESULTSDIR,"peaks","macs2","{sample}.consensus.macs2.peakfiles"),
        replicatePeakFileList=join(RESULTSDIR,"peaks","macs2","{sample}.replicate.macs2.peakfiles"),
        tn5nicksFileList=join(RESULTSDIR,"peaks","macs2","{sample}.macs2.tn5nicksbedfiles")
    container: config["masterdocker"]    
    threads: getthreads("atac_genrich_peakcalling")
    shell:"""
set -e -x -o pipefail
nreplicates=0
for f in {input}
do 
    nreplicates=$((nreplicates+1))
done

cd {params.outdir}

if [ ! -d {params.outdir}/bigwig ];then mkdir -p {params.outdir}/bigwig ;fi
if [ ! -d {params.outdir}/tn5nicks ];then mkdir -p {params.outdir}/tn5nicks ;fi
if [ ! -d {params.qcdir}/peak_annotation ];then mkdir -p {params.qcdir}/peak_annotation;fi

bash {params.scriptsdir}/{params.script} \
    --tagalignfiles {input} \
    --genome {params.genome} \
    --genomefile {params.genomefile} \
    --samplename {params.sample} \
    --scriptsfolder {params.scriptsdir} \
    --outdir {params.outdir} \
    --extsize {params.macs2_extsize} \
    --shiftsize {params.macs2_shiftsize} \
    --runchipseeker {params.macs2_annotatePeaks} \
    --effectivegenomesize {params.macs2_effectiveGenomeSize}

if [ "{params.macs2_annotatePeaks}" == "True" ];then
for g in "annotated" "genelist" "annotation_summary" "annotation_distribution"
do
    for f in `ls *.${{g}}`;do
        rsync -az --progress  --remove-source-files $f {params.qcdir}/peak_annotation/
    done
done
fi

if [ -f {output.tn5nicksFileList} ];then rm -f {output.tn5nicksFileList};fi
if [ -f {output.replicatePeakFileList} ];then rm -f {output.replicatePeakFileList};fi

for f in {input}
do
    repname=`basename $f|awk -F".tagAlign" '{{print $1}}'`
    echo -ne "${{repname}}\t{params.sample}\t{params.outdir}/tn5nicks/${{repname}}.macs2.tn5nicks.bam\n" >> {output.tn5nicksFileList}
    echo -ne "${{repname}}\t{params.sample}\t{params.outdir}/${{repname}}.macs2.narrowPeak\n" >> {output.replicatePeakFileList}
done
echo -ne "{params.sample}\t{params.sample}\t{params.outdir}/{params.sample}.macs2.consensus.bed\n" > {output.consensusPeakFileList}

"""

#########################################################

rule atac_genrich_peakcalling:
# """
# Calling ATACseq peaks using Genrich 
# This is based off of Harvard peak calling for ATACseq data
# Input: Tn5 shifted TagAlign files for each sample (multiple replicates mean multiple tagalign files)
# Output:
# * Genrich peaks per-replicate
# * qvalue-filtered Genrich peaks per-replicate
# * consensus peaks and consensus-qvalue-filtered peaks per-sample
# * ChIPseeker annotations for peaks and filtered peaks (hg38/hg19/mm10/mm9 are currently supported)
# * Tn5 nicks in Bam (and Bed) format
# """
    input:
        unpack(get_replicate_qsortedBamFiles_for_sample)
    params:
        genome=GENOME,
        genomefile=GENOMEFILE,
        outdir=join(RESULTSDIR,"peaks","genrich"),
        scriptsdir=SCRIPTSDIR,
        qcdir=QCDIR,
        script="ccbr_atac_genrich_peak_calling.bash",
        readsbedfolder=join(RESULTSDIR,"tmp","genrichReads"),
        sample="{sample}",
        genrich_s=config["genrich"]["s"],
        genrich_m=config["genrich"]["m"],
        genrich_q=config["genrich"]["q"],
        genrich_l=config["genrich"]["l"],
        genrich_g=config["genrich"]["g"],
        genrich_d=config["genrich"]["d"],
        genrich_annotatePeaks=config["genrich"]["annotatePeaks"],
        genrich_effectiveGenomeSize=config[GENOME]["effectiveGenomeSize"]
    output:
        consensusPeakFileList=join(RESULTSDIR,"peaks","genrich","{sample}.consensus.genrich.peakfiles"),
        replicatePeakFileList=join(RESULTSDIR,"peaks","genrich","{sample}.replicate.genrich.peakfiles"),
        tn5nicksFileList=join(RESULTSDIR,"peaks","genrich","{sample}.genrich.tn5nicksbedfiles")
    container: config["masterdocker"]    
    threads: getthreads("atac_genrich_peakcalling")
    shell:"""
set -e -x -o pipefail
nreplicates=0
for f in {input}
do 
    nreplicates=$((nreplicates+1))
done

cd {params.outdir}

if [ ! -d {params.outdir}/bigwig ];then mkdir -p {params.outdir}/bigwig ;fi
if [ ! -d {params.outdir}/tn5nicks ];then mkdir -p {params.outdir}/tn5nicks ;fi
if [ ! -d {params.qcdir}/peak_annotation ];then mkdir -p {params.qcdir}/peak_annotation;fi
if [ ! -d {params.readsbedfolder} ];then mkdir -p {params.readsbedfolder};fi

bash {params.scriptsdir}/{params.script} \
    --bamfiles {input} \
    --genome {params.genome} \
    --genomefile {params.genomefile} \
    --samplename {params.sample} \
    --scriptsfolder {params.scriptsdir} \
    --genrich_s {params.genrich_s} \
    --genrich_m {params.genrich_m} \
    --genrich_q {params.genrich_q} \
    --genrich_l {params.genrich_l} \
    --genrich_g {params.genrich_g} \
    --genrich_d {params.genrich_d} \
    --runchipseeker {params.genrich_annotatePeaks} \
    --outdir {params.outdir} \
    --readsbedfolder {params.readsbedfolder} \
    --effectivegenomesize {params.genrich_effectiveGenomeSize}

if [ "{params.genrich_annotatePeaks}" == "True" ];then
for g in "annotated" "genelist" "annotation_summary" "annotation_distribution"
do
    for f in `ls *.${{g}}`;do
        rsync -az --progress  --remove-source-files $f {params.qcdir}/peak_annotation/
    done
done
fi

if [ -f {output.tn5nicksFileList} ];then rm -f {output.tn5nicksFileList};fi
if [ -f {output.replicatePeakFileList} ];then rm -f {output.replicatePeakFileList};fi

for f in {input}
do
    repname=`basename $f|awk -F".qsorted.bam" '{{print $1}}'`
    echo -ne "${{repname}}\t{params.sample}\t{params.outdir}/tn5nicks/${{repname}}.genrich.tn5nicks.bam\n" >> {output.tn5nicksFileList}
    echo -ne "${{repname}}\t{params.sample}\t{params.outdir}/${{repname}}.genrich.narrowPeak\n" >> {output.replicatePeakFileList}
done
echo -ne "{params.sample}\t{params.sample}\t{params.outdir}/{params.sample}.genrich.consensus.bed\n" > {output.consensusPeakFileList}

"""

rule motif_enrichment:
# """
# Calculate motif enrichment for replicate (narrowPeak) and sample (consensus.bed) files 
# using HOMER and AME
# """
    input:
        macs2_consensusPeakFileList=join(RESULTSDIR,"peaks","macs2","{sample}.consensus.macs2.peakfiles"),
        macs2_replicatePeakFileList=join(RESULTSDIR,"peaks","macs2","{sample}.replicate.macs2.peakfiles"),
        genrich_consensusPeakFileList=join(RESULTSDIR,"peaks","genrich","{sample}.consensus.genrich.peakfiles"),
        genrich_replicatePeakFileList=join(RESULTSDIR,"peaks","genrich","{sample}.replicate.genrich.peakfiles"),
    params:
        genomefa=GENOMEFA,
        scriptsdir=SCRIPTSDIR,
        script="ccbr_atac_motif_enrichment.bash",
        sample="{sample}",
        homermotif=config[GENOME]["homermotif"],
        mememotif=config[GENOME]["mememotif"]
    output:
        dummy=join(RESULTSDIR,"QC","{sample}.motif_enrichment"),
    container: config["masterdocker"]    
    threads: getthreads("motif_enrichment")
    shell:"""
if [ -w "/lscratch/${{SLURM_JOB_ID}}" ];then tmpdir="/lscratch/${{SLURM_JOB_ID}}";else tmpdir="/dev/shm";fi
 
for narrowPeak in `cat {input}|awk '{{print $NF}}'`;do
    mkdir -p ${{narrowPeak}}_motif_enrichment
    narrowPeak_bn=$(basename $narrowPeak)
    ttmpdir="${{tmpdir}}/$narrowPeak_bn"
    mkdir -p $ttmpdir
    bash {params.scriptsdir}/{params.script} \
        --narrowpeak $narrowPeak \
        --genomefa {params.genomefa} \
        --homermotif {params.homermotif} \
        --mememotif {params.mememotif} \
        --threads {threads} \
        --outdir ${{narrowPeak}}_motif_enrichment \
        --tmpdir $ttmpdir
done

touch {output.dummy}
"""

#########################################################
