#!/usr/bin/env python3
import os
# from snakemake.logging import setup_logger
# setup_logger(debug=True, printshellcmds=True)

configfile: "./config.yaml"

#print(config['Samples']['sampleA']['R1'])
#print(config['Samples']['sampleB']['R1'])

reference=config['Reference']
analysis_samples = config['Samples'].keys()
os.chdir(config['projectdir'])
projectdir = config['projectdir']
print("Working directory ", projectdir)

rule all:
    input:
        expand("{projectdir}/results/bowtie_mapping/{sample}/alignment_sorted.bam", projectdir=config['projectdir'],                sample=analysis_samples)

rule trimmomatic:
    input:
        R1=lambda wildcards: config['Samples'][wildcards.sample]['R1'],
        R2=lambda wildcards: config['Samples'][wildcards.sample]['R2']
        # R1=config['Samples'][sample]['R1'],
        # R2=config['Samples'][sample]['R2']
    output:
        R1Paired="{projectdir}/results/trimmomatic/{sample}/R1_paired.fastq.gz",
        R1Unpaired="{projectdir}/results/trimmomatic/{sample}/R1_unpaired.fastq.gz",
        R2Paired="{projectdir}/results/trimmomatic/{sample}/R2_paired.fastq.gz",
        R2Unpaired="{projectdir}/results/trimmomatic/{sample}/R2_unpaired.fastq.gz"
    message:
        'Running Quality Control using Trimmomatic '
    log: "{projectdir}/logs/{sample}/trimmomatic.log"
    benchmark: "{projectdir}/benchmarks/{sample}.trimmomatic.benchmark.txt"
    threads : 4
    shell: "trimmomatic PE -threads 4  -phred33 -trimlog {log} {input.R1} {input.R2} {output} SLIDINGWINDOW:4:20 MINLEN:30"

rule bowtie_indexing:
    input: config['Reference']
    output: config["Reference"] + ".1.bt2", config["Reference"] + ".2.bt2", config["Reference"] + ".3.bt2", config["Reference"] + ".4.bt2", config["Reference"] + ".rev.1.bt2", config["Reference"] + ".rev.2.bt2"
    message: "Bowtie Indexing for reference"
    threads: 4
    benchmark: "benchmarks/reference.bowtie2index.benchmark.txt"
    conda: "envs/bowtie2.yaml"
    shell: "bowtie2-build -f {input} {input}"

rule bowtie_mapping:
    input:
        R1="{projectdir}/results/trimmomatic/{sample}/R1_paired.fastq.gz",
        R2="{projectdir}/results/trimmomatic/{sample}/R2_paired.fastq.gz",
        index=[config["Reference"] + ".1.bt2", config["Reference"] + ".2.bt2", config["Reference"] + ".3.bt2", config["Reference"] + ".4.bt2", config["Reference"] + ".rev.1.bt2", config["Reference"] + ".rev.2.bt2"]
    output: temp("{projectdir}/results/bowtie_mapping/{sample}/alignment.sam")
    log: "{projectdir}/logs/{sample}/bowtie_mapping.log"
    message: "Aligning reads with Bowtie2"
    benchmark: "{projectdir}/benchmarks/{sample}.bowtie2.benchmark.txt"
    threads : 4
    conda:
        "envs/bowtie2.yaml"
    shell:
        "bowtie2 -x {reference} --maxins 1000  -1 {input.R1} -2 {input.R2} -S {output}"

rule samtobam:
    input: "{projectdir}/results/bowtie_mapping/{sample}/alignment.sam"
    output: temp("{projectdir}/results/bowtie_mapping/{sample}/alignment.bam")
    log: "{projectdir}/logs/{sample}/samtobam.log"
    message:"Converting sam to bam for"
    threads: 2
    benchmark: "{projectdir}/benchmarks/{sample}.samtobam.benchmark.txt"
    conda: "envs/samtools.yaml"
    shell: "samtools view -b -T {reference} -o {output} {input}"

rule sort_bam:
    input: "{projectdir}/results/bowtie_mapping/{sample}/alignment.bam"
    output: protected("{projectdir}/results/bowtie_mapping/{sample}/alignment_sorted.bam")
    log: "{projectdir}/logs/{sample}/sort_bam.log"
    message: "Sorting BAM file"
    benchmark: "{projectdir}/benchmarks/{sample}.bamsort.benchmark.txt"
    threads: 4
    conda: "envs/samtools.yaml"
    shell: "samtools sort -l 5 -o {output} {input} && samtools index {output}"   # -l option is compress level.

rule run_bowtie:
    input: expand(["{projectdir}/results/bowtie_mapping/{sample}/alignment_sorted.bam"], projectdir=projectdir, sample=analysis_samples)


rule merge_bamfiles:
    input: expand(["{projectdir}/results/bowtie_mapping/{sample}/alignment_sorted.bam"], sample=analysis_samples, projectdir=projectdir)
    output: "{projectdir}/results/bowtie_mapping/merged_samples/merged.bam"
    log: "{projectdir}/logs/merged_samples/bamfiles_merged.log"
    message: "Merging bam files"
    threads: 2
    benchmark: "{projectdir}/benchmarks/merging_bamfiles.benchmark.txt"
    shell: "samtools merge --reference {reference} {output} {input} && samtools index {output}"

rule run_merge_bam:
    input: "{projectdir}/results/bowtie_mapping/merged_samples/merged.bam".format(projectdir=projectdir)

rule assembly_polish:
    input:
        assembly = config['Reference'],
        bamfile = "{projectdir}/results/bowtie_mapping/merged_samples/merged.bam"
    output: "{projectdir}/results/pilon/pilon_polished_assembly.fasta"
    log: "{projectdir}/logs/assembly_polish/polished_assembly.log"
    message: "Polishing asssembly"
    threads: 4
    benchmark: "{projectdir}/benchmarks/assembly_polish.benchmark.txt"
    shell: "pilon --genome {input.assembly} --output pilon_polished_assembly --outdir {projectdir}/results/pilon/ --changes --frags {input.bamfile} --fix snps,indels,gaps --duplicates --diploid"

rule analysis:
    input: "{projectdir}/results/pilon/pilon_polished_assembly.fasta".format(projectdir=projectdir)

onsuccess: "snakemake has completed sucessfully"

onfailure: "snakemake has failed. Please talk to this worflow programmer to resolve the failure"
