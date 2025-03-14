"""
all rules/logic related to the final UCSC trackhub (or assembly hub) should be here.
"""
if config.get("create_trackhub"):
    import logging
    import os.path
    import re

    import trackhub

    from seq2science.util import color_picker, color_gradient, hsv_to_ucsc, shorten


    # remove the logger created by trackhub (in trackhub.upload)
    # (it adds global logging of all stdout messages, duplicating snakemake's logging)
    if len(logging.root.handlers):
        th_handler = logging.root.handlers[-1]  # assumption: the last logger was added by trackhub
        logging.root.removeHandler(th_handler)
        del logging


    rule twobit:
        """
        Generate a 2bit file for each assembly
        """
        input:
            rules.get_genome.output,
        output:
            expand("{genome_dir}/{{assembly}}/{{assembly}}.2bit", **config),
        log:
            expand("{log_dir}/trackhub/{{assembly}}.2bit.log", **config),
        benchmark:
            expand("{benchmark_dir}/trackhub/{{assembly}}.2bit.benchmark.txt", **config)[0]
        conda:
            "../envs/ucsc.yaml"
        shell:
            """
            faToTwoBit {input} {output} >> {log} 2>&1
            """


    rule gcPercent:
        """
        Generate a gc content track
    
        source: http://hgdownload.cse.ucsc.edu/goldenPath/hg19/gc5Base/
        """
        input:
            twobit=rules.twobit.output,
            sizes=rules.get_genome_support_files.output.sizes,
        output:
            gcpcvar=temp(expand("{genome_dir}/{{assembly}}/{{assembly}}.gc5Base.wigVarStep.txt.gz", **config)),
            gcpc=expand("{genome_dir}/{{assembly}}/{{assembly}}.gc5Base.bw", **config),
        log:
            expand("{log_dir}/trackhub/{{assembly}}.gc5Base.log", **config),
        benchmark:
            expand("{benchmark_dir}/trackhub/{{assembly}}.gc5Base.benchmark.txt", **config)[0]
        resources:
            mem_gb=5,
        conda:
            "../envs/ucsc.yaml"
        shell:
            """
            hgGcPercent -wigOut -doGaps -file=stdout -win=5 -verbose=0 {wildcards.assembly} {input.twobit} \
                | gzip > {output.gcpcvar}
    
            wigToBigWig {output.gcpcvar} {input.sizes} {output.gcpc} >> {log} 2>&1
            """


    rule cytoband:
        """
        Generate a cytoband track for each assembly
    
        source: http://genomewiki.ucsc.edu/index.php/Assembly_Hubs#Cytoband_Track
        """
        input:
            genome=rules.get_genome.output,
            sizes=rules.get_genome_support_files.output.sizes,
        output:
            cytoband_bb=expand("{genome_dir}/{{assembly}}/cytoBandIdeo.bb", **config),
            cytoband_bd=temp(expand("{genome_dir}/{{assembly}}/cytoBandIdeo.bed", **config)),
        params:
            schema=f"{config['rule_dir']}/../schemas/cytoBand.as",
        log:
            expand("{log_dir}/trackhub/{{assembly}}.cytoband.log", **config),
        benchmark:
            expand("{log_dir}/trackhub/{{assembly}}.cytoband.benchmark.txt", **config)[0]
        conda:
            "../envs/ucsc.yaml"
        shell:
            """
            cat {input.sizes} | 
            bedSort /dev/stdin /dev/stdout | 
            awk '{{print $1,0,$2,$1,"gneg"}}' > {output.cytoband_bd}
    
            bedToBigBed -type=bed4 {output.cytoband_bd} -as={params.schema} \
            {input.sizes} {output.cytoband_bb} >> {log} 2>&1
            """


    rule softmask_track_1:
        """
        Generate a track of all softmasked regions
    
        source: https://github.com/Gaius-Augustus/MakeHub/blob/master/make_hub.py
        """
        input:
            genome=rules.get_genome.output,
        output:
            mask_unsorted=temp(expand("{genome_dir}/{{assembly}}/{{assembly}}_softmasking_unsorted.bed", **config)),
        benchmark:
            expand("{benchmark_dir}/trackhub/{{assembly}}.softmask1.benchmark.txt", **config)[0]
        threads: 4
        resources:
            mem_gb=2,
        retries: 2
        script:
            f"{config['rule_dir']}/../scripts/softmask.py"


    rule softmask_track_2:
        """
        Generate a track of all softmasked regions
    
        source: https://github.com/Gaius-Augustus/MakeHub/blob/master/make_hub.py
        """
        input:
            mask_unsorted=rules.softmask_track_1.output.mask_unsorted,
            sizes=rules.get_genome_support_files.output.sizes,
        output:
            maskbed=temp(expand("{genome_dir}/{{assembly}}/{{assembly}}_softmasking.bed", **config)),
            mask=expand("{genome_dir}/{{assembly}}/{{assembly}}_softmasking.bb", **config),
        log:
            expand("{log_dir}/trackhub/{{assembly}}.softmask.log", **config),
        benchmark:
            expand("{benchmark_dir}/trackhub/{{assembly}}.softmask2.benchmark.txt", **config)[0]
        conda:
            "../envs/ucsc.yaml"
        shell:
            """
            bedSort {input.mask_unsorted} {output.maskbed} >> {log} 2>&1
    
            bedToBigBed -type=bed3 {output.maskbed} {input.sizes} {output.mask} >> {log} 2>&1
            """


    rule trackhub_index:
        """
        Generate a searchable annotation & index for each assembly
    
        sources: https://genome.ucsc.edu/goldenPath/help/hubQuickStartSearch.html, 
        https://www.biostars.org/p/272649/
        """
        input:
            sizes=rules.get_genome_support_files.output.sizes,
            gtf=rules.get_genome_annotation.output.gtf,
        output:
            gtf_min_size=temp(expand("{genome_dir}/{{assembly}}/{{assembly}}.annotation_minsize.gtf", **config)),
            genePred=temp(expand("{genome_dir}/{{assembly}}/{{assembly}}.gp", **config)),
            genePrednamed=temp(expand("{genome_dir}/{{assembly}}/{{assembly}}named.gp", **config)),
            genePredbed=temp(expand("{genome_dir}/{{assembly}}/{{assembly}}.gp.bed", **config)),
            genePredbigbed=expand("{genome_dir}/{{assembly}}/annotation.bigBed", **config),
            info=temp(expand("{genome_dir}/{{assembly}}/info.txt", **config)),
            indexinfo=temp(expand("{genome_dir}/{{assembly}}/indexinfo.txt", **config)),
            ix=expand("{genome_dir}/{{assembly}}/annotation.ix", **config),
            ixx=expand("{genome_dir}/{{assembly}}/annotation.ixx", **config),
        log:
            expand("{log_dir}/trackhub/{{assembly}}.index.log", **config),
        benchmark:
            expand("{benchmark_dir}/trackhub/{{assembly}}.index.benchmark.txt", **config)[0]
        message: EXPLAIN["trackhub"]
        conda:
            "../envs/ucsc.yaml"
        shell:
            """
            # filter out tiny tiny transcripts that make gtftogenepred fail
            min_transcript_length=15
            (awk -v minlen=$min_transcript_length 'BEGIN {{ FS = "\\t"; OFS="\\t" }}; {{ if(($3=="transcript") && ($5 - $4 <= minlen)) {{ print $9 }} }}' {input.gtf} | grep . || echo "transcript_id \\\"DONTMATCHANYTHING\\\"") | grep -oP '(?<=transcript_id ").+?(?=")' | grep -v -f - {input.gtf} > {output.gtf_min_size} 2>> {log}

            # generate annotation files
            gtfToGenePred -allErrors -ignoreGroupsWithoutExons -geneNameAsName2 -genePredExt {output.gtf_min_size} {output.genePred} -infoOut={output.info} >> {log} 2>&1
    
            # if gtf has gene_names, use gene_names, else transcript_id
            if grep -Fq "gene_name" {output.gtf_min_size}; then n=1; else n=0; fi
    
            # switch columns 1 (transcript_id) and 12 (gene_name)
            awk -v n=$n 'BEGIN {{ FS = "\\t"; OFS="\\t" }}; {{ if(n==1) {{ t = $1; $1 = $12; $12 = t; print; }} else {{ print; }} }}' {output.genePred} > {output.genePrednamed}
    
            # remove lines with an empty first column (e.g. no gene names for ERCC RNA spike-in)
            grep -vP "^\t" {output.genePrednamed} > {output.genePred}

            # remove spaces from the genePred (error in annotation)
            sed -i 's/ //g' {output.genePred}
    
            genePredToBed {output.genePred} {output.genePredbed} >> {log} 2>&1
    
            bedSort {output.genePredbed} {output.genePredbed} >> {log} 2>&1
    
            bedToBigBed -extraIndex=name {output.genePredbed} {input.sizes} {output.genePredbigbed} >> {log} 2>&1
    
            # generate searchable indexes (by 1: transcriptID, 2: geneId, 8: proteinID, 9: geneName, 10: transcriptName)
            grep -v "^#" {output.info} | awk -v n=$n 'BEGIN {{ FS = "\\t"; OFS="\\t" }} ; {{ if(n==1) {{print $9, $1, $2, $8, $9, $10}} else {{print $1, $1, $2, $8, $9, $10}} }}' > {output.indexinfo}
    
            ixIxx {output.indexinfo} {output.ix} {output.ixx} >> {log} 2>&1
            """


    def get_ucsc_name(assembly):
        """
        Returns as first value (bool) whether the assembly was found to be in the
        ucsc genome browser, and as second value the name of the assembly according to ucsc
        "convention".
        """
        # strip custom prefix, if present
        assembly = ORI_ASSEMBLIES[assembly]

        # patches are not relevant for which assembly it belongs to
        # (at least not human and mouse)
        assembly_np = [split for split in re.split(r"(.+)(?=\.p\d)", assembly) if split != ""][0].lower()

        # check if the assembly matches an ucsc assembly name
        if assembly_np in UCSC_ASSEMBLIES:
            return True, UCSC_ASSEMBLIES[assembly_np][0]

        # else check if it is part of the description
        for ucsc_assembly, desc in UCSC_ASSEMBLIES.values():
            assemblies = desc[desc.find("(") + 1 : desc.find(")")].split("/")
            assemblies = [val.lower() for val in assemblies]
            if assembly_np in assemblies:
                return True, ucsc_assembly

        # if not found, return the original name
        return False, assembly

    # check if trackhubs are available on ucsc (in case we dont force an assembly hub)
    if config.get("force_assembly_hub", False):
        ucsc_names = {a: (False, a) for a in ALL_ASSEMBLIES}
    else:
        ucsc_names = {a: get_ucsc_name(a) for a in ALL_ASSEMBLIES}

    def get_defaultpos(sizefile):
        # extract a default position spanning the first scaffold/chromosome in the sizefile.
        with open(sizefile, "r") as file:
            dflt = file.readline().strip("\n").split("\t")
        return dflt[0] + ":0-" + str(min(int(dflt[1]), 100000))


    def get_colors(asmbly):
        """
        Return a dictionary with colors for each track.

        First picks a color for each main track (biological replicates for ATAC-/ChIP-seq or
        forward stranded technical replicate for alignment/RNA-seq).
        Main track colors can be specified in the samples.tsv, in column 'colors'.

        Then add paler colors for each sub track.
        """
        palletes = {}

        # get a dataframe with one color per biological replicate
        df = breps[(breps["assembly"] == asmbly) & (~breps.index.duplicated(keep='first'))]
        
        # pick main colors for each main track
        main_tracks = df.index.to_list()
        if "colors" in breps:
            mc = df["colors"].to_list()
        else:
            mc = color_picker(len(main_tracks))

        # create a gradient for each main track color
        for n, rep in enumerate(main_tracks):
            # ATAC-/ChIP-seq: 1 for breps + 1 per trep. RNA-seq: 1 for forward/reverse strand
            tracks_per_main_track = 1 + len(TREPS_FROM_BREP[(rep, asmbly)])
            palletes[rep] = color_gradient(mc[n], tracks_per_main_track)

        return palletes


    def strandedness_in_assembly(assembly):
        """
        Check if there are any stranded samples for this assembly.
        Returns False if no reports have been generated yet.
        """
        if WORKFLOW != "rna_seq":
            return False

        asmbly = ORI_ASSEMBLIES[assembly]  # no custom suffix, if present
        for trep in treps[treps["assembly"] == asmbly].index:
            if is_standed(assembly, trep):
                return True
        return False


    def is_standed(assembly, trep):
        """
        Check if the sample is stranded.
        Returns False if the report has not been generated yet.
        """
        report_file = os.path.join(
            config['qc_dir'], "strandedness", f"{assembly}-{trep}.strandedness.txt"
        )
        strandedness = get_strandedness(report_file)
        if strandedness in ["no", "placeholder"]:
            return False
        return True


    def create_trackhub():
        """
        Create a UCSC trackhub.
        Returns the hub, and a list of required files.

        Birds eye view of the trackhub system:
        hub
        └──genomes_file
           └──genome (1 per assembly)
              ├──trackdb
              |  ├── annotation files (assembly hub only)
              |  └── peaks, bigwigs
              └──groups_file (assembly hub only)

        trackdb
        ├──(annotation group annotation assembly hub only)
        ├──(gcPercent  group annotation assembly hub only)
        ├──(softmasked group annotation assembly hub only)
        |
        └──composite (1 per peak caller, group trackhub - assembly hub only)
           ├──view: peaks  (forward strand/unstranded for Alignment/RNA-seq)
           ├──view: signal (reverse strand for Alignment/RNA-seq)
           ├──----brep1               view peak, subgroup brep
           ├──----brep1 trep1         view signal, subgroup brep
           ├──----brep1 trep1_control view signal, subgroup brep
           └──----brep1 trep2         view signal, subgroup brep
        """
        out = {
            "hub": None,  # the complete trackhub
            "files": []  # the files required (for the snakemake input)
        }

        # universal hub file
        hub = trackhub.Hub(
            hub=config.get("hubname", f"{SEQUENCING_PROTOCOL}_trackhub"),
            short_label=config.get(
                "shortlabel", f"Seq2science {SEQUENCING_PROTOCOL} hub"
            ),  # title of the control box in the genome browser (for trackhubs)
            long_label=config.get(
                "longlabel",
                f"Automated {SEQUENCING_PROTOCOL} trackhub generated by seq2science: \nhttps://github.com/vanheeringen-lab/seq2scsience",
            ),
            email=config.get("email", "none@provided.com"),
        )
        out["hub"] = hub

        # universal genomes file
        genomes_file = trackhub.genomes_file.GenomesFile()
        hub.add_genomes_file(genomes_file)

        for assembly in ALL_ASSEMBLIES:
            asmbly = ORI_ASSEMBLIES[assembly]  # no custom suffix, if present
            hub_type = "trackhub" if ucsc_names[assembly][0] else "assembly_hub"
            trackdb = trackhub.trackdb.TrackDb()
            palletes = get_colors(asmbly)
            priority = 10.0

            if hub_type == "trackhub":
                # link this data to the existing trackhub
                assembly_uscs = ucsc_names[assembly][1]
                genome = trackhub.Genome(assembly_uscs)

            elif hub_type == "assembly_hub":
                # add the files for an assembly hub

                # the genome
                file = f"{config['genome_dir']}/{assembly}/{assembly}.2bit"
                sizes_file = f"{config['genome_dir']}/{assembly}/{assembly}.fa.sizes"
                dflt = get_defaultpos(sizes_file) if os.path.exists(sizes_file) else "chr1:0-10000"  # placeholder
                genome = trackhub.Assembly(
                    genome=asmbly,
                    twobit_file=file,
                    organism=asmbly,
                    defaultPos=dflt,
                    scientificName=asmbly,
                    description=asmbly,
                )
                out["files"].append(file)
                out["files"].append(sizes_file)

                # groups_file
                annotation_group = trackhub.groups.GroupDefinition(
                    name="annotation",
                    label="Gene and Genome Annotation",
                    priority=1,  # group priority overrules track priority
                    default_is_closed=True,
                )
                hub_group = trackhub.groups.GroupDefinition(
                    name="trackhub",
                    label=config.get("shortlabel", f"seq2science {SEQUENCING_PROTOCOL} hub"),
                    priority=2,  # group priority overrules track priority
                    default_is_closed=False,
                )
                groups_file = trackhub.groups.GroupsFile([annotation_group, hub_group])
                genome.add_groups(groups_file)

                # annotation tracks
                file = f"{config['genome_dir']}/{assembly}/cytoBandIdeo.bb"
                track = trackhub.Track(
                    name="cytoBandIdeo",
                    tracktype="bigBed",
                    short_label="cytoBandIdeo",
                    long_label="Chromosome ideogram with cytogenetic bands",
                    source=file,
                )
                trackdb.add_tracks(track)
                out["files"].append(file)

                file = f"{config['genome_dir']}/{assembly}/{assembly}.gc5Base.bw"
                track = trackhub.Track(
                    name="gcPercent",
                    source=file,
                    tracktype="bigWig",
                    visibility="dense",
                    color="59,189,191",  # cyan
                    group="annotation",
                    priority=1,
                )
                trackdb.add_tracks(track)
                out["files"].append(file)

                file = f"{config['genome_dir']}/{assembly}/{assembly}_softmasking.bb"
                track = trackhub.Track(
                    name="softmasked",
                    source=file,
                    tracktype="bigBed",
                    visibility="dense",
                    color="128,128,128",  # grey
                    group="annotation",
                    priority=2,
                )
                trackdb.add_tracks(track)
                out["files"].append(file)

                # add gtf-dependent track(s) if possible
                if HAS_ANNOTATION[assembly]:
                    file = f"{config['genome_dir']}/{assembly}/annotation.bigBed"
                    track = trackhub.Track(
                        name="annotation",
                        source=file,
                        tracktype="bigBed 12",
                        visibility="pack",
                        color="140,43,69",  # bourgundy
                        group="annotation",
                        priority=3,
                        searchIndex="name",
                        searchTrix="annotation.ix",  # searchable by name
                    )
                    trackdb.add_tracks(track)
                    out["files"].append(file)
                    out["files"].append(f"{config['genome_dir']}/{assembly}/annotation.ix")
                    out["files"].append(f"{config['genome_dir']}/{assembly}/annotation.ixx")

            genomes_file.add_genome(genome)
            genome.add_trackdb(trackdb)

            # workflow specific data
            if WORKFLOW in ["atac_seq", "chip_seq"]:
                for peak_caller in config["peak_caller"]:
                    ftype = get_peak_ftype(peak_caller)
                    ttype = "bigNarrowPeak" if ftype == "narrowPeak" else "bigBed"
                    peak_caller_suffix = "" if len(config["peak_caller"]) == 1 else f" {peak_caller}"
                    pcs = shorten(peak_caller_suffix, 5)
                    peak_caller_prefix = "" if len(config["peak_caller"]) == 1 else f"{peak_caller} "
                    pcp = shorten(peak_caller_prefix, 5)
                    peak_caller_sort_order = {
                        "macs2": "coordinate",
                        "genrich": "queryname",
                    }[peak_caller]
                    peak_caller_sorter = {
                        "macs2": "samtools",
                        "genrich": "sambamba",
                    }[peak_caller]

                    # one composite track to rule them all...
                    name = f"{SEQUENCING_PROTOCOL}{peak_caller_suffix} samples"
                    safename = trackhub.helpers.sanitize(name)
                    composite = trackhub.CompositeTrack(
                        name=safename,
                        short_label=f"{SEQUENCING_PROTOCOL}{pcs}",
                        long_label=name,
                        dimensions=f"dimX=view dimY=conditions",
                        tracktype="bigWig",
                        visibility="dense",  # to keep loading times managable
                        # autoScale="group",  # the package cannot handle this composite-bigwig-only option. Added later.
                    )
                    if hub_type == "assembly_hub":
                        composite.add_params(group="trackhub")
                    trackdb.add_tracks(composite)

                    # ...one view to find them...
                    peaks_view_name = f"{peak_caller_prefix}peaks"
                    peaks_view = trackhub.ViewTrack(
                        name=trackhub.helpers.sanitize(peaks_view_name),
                        short_label=f"{pcp}peaks",  # <= 17 characters suggested
                        long_label=peaks_view_name,
                        view="peaks",
                        visibility="dense",  # peaks aren't nice beyond dense
                        tracktype=ttype,
                    )
                    composite.add_view(peaks_view)

                    # ...one view to bring them all...
                    signal_view_name = f"{peak_caller_prefix}signal"
                    signal_view = trackhub.ViewTrack(
                        name=trackhub.helpers.sanitize(signal_view_name),
                        short_label=f"{pcp}signal",  # <= 17 characters suggested
                        long_label=signal_view_name,
                        view="signal",
                        visibility="full",  # default
                        maxHeightPixels="100:50:8",  # with 50 the y-axis is visible
                        tracktype="bigWig",
                    )
                    composite.add_view(signal_view)

                    # input control view
                    if "control" in treps:
                        control_view = trackhub.ViewTrack(
                            name=trackhub.helpers.sanitize("input control"),
                            short_label=f"control",  # <= 17 characters suggested
                            long_label="input control",
                            view="control",
                            visibility="full",  # default
                            maxHeightPixels="100:50:8",  # with 50 the y-axis is visible
                            tracktype="bigWig",
                        )
                        composite.add_view(control_view)


                    # ...and in subgroup bind them.
                    subgroup = trackhub.SubGroupDefinition(
                        name="conditions", label="Conditions", mapping={}  # breps are added to this filter
                    )
                    composite.add_subgroups([subgroup])

                    # add the actual tracks
                    for brep in list(set(breps[breps["assembly"] == asmbly].index)):
                        descriptive = rep_to_descriptive(brep, brep=True)
                        safedescr = trackhub.helpers.sanitize(descriptive)
                        subgroup.mapping[safedescr] = descriptive

                        file = f"{config['result_dir']}/{peak_caller}/{assembly}-{brep}.big{ftype}"
                        priority += 1.0
                        track = trackhub.Track(
                            name=trackhub.helpers.sanitize(f"{descriptive}{peak_caller_suffix} pk"),
                            tracktype=ttype,
                            short_label=f"{shorten(descriptive, 14-len(pcs), ['signs', 'vowels', 'center'])}{pcs} pk",  # <= 17 characters suggested
                            long_label=f"{descriptive}{peak_caller_suffix} peaks",
                            subgroups={"conditions": safedescr},
                            source=file,
                            visibility="full",  # full/squish/pack/dense/hide visibility of the track
                            color=hsv_to_ucsc(palletes[brep][0]),
                            priority=priority,  # the order this track will appear in
                        )
                        if ttype != "bigNarrowPeak":
                            track.autoScale = ("on",)  # allow the track to autoscale
                            track.maxHeightPixels = "100:50:8"  # with 50 the y-axis is shown
                        out["files"].append(file)
                        peaks_view.add_tracks(track)

                        # the technical replicate(s) that comprise this biological replicate
                        for n, trep in enumerate(TREPS_FROM_BREP[(brep, asmbly)]):
                            file = f"{config['result_dir']}/{peak_caller}/{assembly}-{trep}.bw"
                            priority += 1.0
                            track = trackhub.Track(
                                name=trackhub.helpers.sanitize(f"{rep_to_descriptive(trep)}{peak_caller_suffix} bw"),
                                tracktype="bigWig",
                                short_label=f"{shorten(rep_to_descriptive(trep), 14-len(pcs), ['signs', 'vowels', 'center'])}{pcs} bw",  # <= 17 characters suggested
                                long_label=f"{rep_to_descriptive(trep)}{peak_caller_suffix} bigWig",
                                subgroups={"conditions": safedescr},
                                source=file,
                                visibility="full",  # full/squish/pack/dense/hide visibility of the track
                                color=hsv_to_ucsc(palletes[brep][n + 1]),
                                priority=priority,  # the order this track will appear in
                            )
                            out["files"].append(file)
                            signal_view.add_tracks(track)

                            # add the control sample(s)
                            if "control" in treps and isinstance(treps.loc[trep, "control"], str):
                                control_name = treps.loc[trep, "control"]

                                file = f"{config['bigwig_dir']}/{assembly}-{control_name}.{peak_caller_sorter}-{peak_caller_sort_order}.bw"
                                priority += 1.0
                                track = trackhub.Track(
                                    name=trackhub.helpers.sanitize(f"{rep_to_descriptive(trep)}_control bw"),
                                    tracktype="bigWig",
                                    short_label=f"{shorten(rep_to_descriptive(trep), 14-len(pcs), ['signs', 'vowels', 'center'])}_control{pcs} bw",  # <= 17 characters suggested
                                    long_label=f"{rep_to_descriptive(trep)}_control{peak_caller_suffix} bigWig",
                                    subgroups={"conditions": safedescr},
                                    source=file,
                                    visibility="full",  # full/squish/pack/dense/hide visibility of the track
                                    color=hsv_to_ucsc(palletes[brep][n + 1]),
                                    priority=priority,  # the order this track will appear in
                                )
                                out["files"].append(file)
                                control_view.add_tracks(track)


            elif WORKFLOW in ["alignment", "rna_seq"]:
                has_strandedness = strandedness_in_assembly(assembly)

                # one composite track to rule them all...
                name = f"{SEQUENCING_PROTOCOL} samples"
                safename = trackhub.helpers.sanitize(name)
                composite = trackhub.CompositeTrack(
                    name=safename,
                    short_label=SEQUENCING_PROTOCOL,
                    long_label=name,
                    dimensions=f"dimX=view dimY=samples",
                    tracktype="bigWig",
                    visibility="dense",  # to keep loading times managable
                    # autoScale="group",  # the package cannot handle this composite-bigwig-only option. Added later.
                )
                if hub_type == "assembly_hub":
                    composite.add_params(group="trackhub")
                trackdb.add_tracks(composite)

                # ...one view to find them...
                fwd_view_name = "forward strand/unstranded reads"
                fwd_view = trackhub.ViewTrack(
                    name=trackhub.helpers.sanitize(fwd_view_name),
                    short_label="fwd/all reads",  # <= 17 characters suggested
                    long_label=fwd_view_name,
                    view="forward",
                    visibility="full",  # default
                    maxHeightPixels="100:50:8",  # with 50 the y-axis is visible
                    tracktype="bigWig",
                )
                composite.add_view(fwd_view)

                # ...one view to bring them all...
                if has_strandedness:  # only added if there are reverse strand bams
                    rev_view_name = "reverse strand reads"
                    rev_view = trackhub.ViewTrack(
                        name=trackhub.helpers.sanitize(rev_view_name),
                        short_label="rev reads",  # <= 17 characters suggested
                        long_label=rev_view_name,
                        view="reverse",
                        visibility="full",  # default
                        maxHeightPixels="100:50:8",  # with 50 the y-axis is visible
                        tracktype="bigWig",
                    )
                    composite.add_view(rev_view)

                # ...and in subgroup bind them.
                subgroup = trackhub.SubGroupDefinition(
                    name="samples", label="Samples", mapping={}  # breps are added to this filter
                )
                composite.add_subgroups([subgroup])

                # add the actual tracks
                for trep in treps[treps["assembly"] == asmbly].index:
                    descriptive = rep_to_descriptive(trep)
                    safedescr = trackhub.helpers.sanitize(descriptive)
                    subgroup.mapping[safedescr] = descriptive

                    # unstranded/forward strand
                    file = f"{config['bigwig_dir']}/{assembly}-{trep}.{config['bam_sorter']}-{config['bam_sort_order']}.bw"
                    priority += 1.0
                    track = trackhub.Track(
                        name=trackhub.helpers.sanitize(f"{descriptive}"),
                        tracktype="bigWig",
                        short_label=shorten(descriptive,17,["signs", "vowels", "center"]),  # <= 17 characters suggested
                        long_label=descriptive,
                        subgroups={"samples": safedescr},
                        source=file,
                        visibility="full",# full/squish/pack/dense/hide visibility of the track
                        color=hsv_to_ucsc(palletes[trep][0]),
                        priority=priority,# the order this track will appear in
                    )
                    out["files"].append(file)
                    fwd_view.add_tracks(track)

                    # reverse strand
                    if has_strandedness and is_standed(assembly, trep):
                        file = f"{config['bigwig_dir']}/{assembly}-{trep}.{config['bam_sorter']}-{config['bam_sort_order']}.rev.bw"
                        priority += 1.0
                        track = trackhub.Track(
                            name=trackhub.helpers.sanitize(f"{descriptive} reverse"),
                            tracktype="bigWig",
                            short_label=shorten(descriptive,14,["signs", "vowels", "center"]) + " rv",# <= 17 characters suggested
                            long_label=descriptive + " reverse",
                            subgroups={"samples": safedescr},
                            source=file,
                            visibility="full",# full/squish/pack/dense/hide visibility of the track
                            color=hsv_to_ucsc(palletes[trep][1]),
                            priority=priority,# the order this track will appear in
                        )
                        # out["files"].append(file)
                        rev_view.add_tracks(track)

        return out


    # generate this once
    trackhub_files = create_trackhub()["files"]


    rule trackhub:
        """
        Generate a UCSC track hub/assembly hub. 
    
        To view the hub, the output directory must be hosted on an web accessible location, 
        and the location of the hub.txt file given the UCSC genome browser at 
        My Data > Track Hubs > My Hubs
        """
        input:
            trackhub_files,
        output:
            directory(config["trackhub_dir"]),
        message: EXPLAIN["trackhub"]
        log:
            expand("{log_dir}/trackhub/trackhub.log", **config),
        benchmark:
            expand("{benchmark_dir}/trackhub/trackhub.benchmark.txt", **config)[0]
        params:
            hub=create_trackhub()["hub"],  # generate when files are complete
            genomes_dir=config['genome_dir'],
            ALL_ASSEMBLIES=ALL_ASSEMBLIES,
            ORI_ASSEMBLIES=ORI_ASSEMBLIES,
            ucsc_names=ucsc_names,
            HAS_ANNOTATION=HAS_ANNOTATION,
        script:
            f"{config['rule_dir']}/../scripts/trackhub.py"


    localrules:
        softmask_track_1,
        trackhub,
