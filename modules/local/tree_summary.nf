process TREE_SUMMARY {
    tag "$meta.id"
    label 'process_single'

    container = 'fduarte001/genomeqc_tree:0.1'
    publishDir "$params.outdir/tree_plots" , mode: "${params.publish_dir_mode}", pattern:"Phyloplot_*.pdf"

    input:
    tuple val(meta), path(tree)
    path  multiqc_files

    output:
    path( "P*.pdf"          ),                emit: figure
    path( "versions.yml"    ),                emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    #Remove unwanted extensions in the tree file
    sed \'s/\\.prot\\.fa\\.largestIsoform//g\' ${tree}/Species_Tree/SpeciesTree_rooted_node_labels.txt > tree.nw

    # Combine GENE OVERLAPS outputs
    gene_overlaps_table.py Count.*.tsv gene_stats.tsv --include-sense --include-antisense

    # Combine NUMBER SEQS outputs
    # Add header
    echo -e "species\tchromosome_count\tsequence_count" > number_seqs.tsv
    tail -n +2 -q *.n_seqs.tsv >> number_seqs.tsv

    # Combine the BUSCO outputs and remove empty tabs
    head -qn 1 *.txt | head -n 1                                > Busco_combined
    tail -q -n 1 *.txt | sed -E 's/\t+/\t/g' | sed 's/\t\$//g' >> Busco_combined

    # Combine QUAST ouput
    quast_2_table.py *quast.tsv -o Quast_to_plot.tsv -col N50,N90,"Total length","GC (%)","# contigs" -plot_types bar,bar,bar,bar

    # Run summary plot
    plot_tree_summary.R tree.nw Busco_combined Quast_to_plot.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Perl version: \$(perl --version | grep "version" | sed 's/.*(//g' | sed 's/[)].*//')
        Python version: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """

}
