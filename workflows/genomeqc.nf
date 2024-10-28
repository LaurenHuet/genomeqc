/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { CREATE_PATH                         } from '../modules/local/create_path'
include { NCBIGENOMEDOWNLOAD                  } from '../modules/nf-core/ncbigenomedownload/main'
include { PIGZ_UNCOMPRESS as UNCOMPRESS_FASTA } from '../modules/nf-core/pigz/uncompress/main'
include { PIGZ_UNCOMPRESS as UNCOMPRESS_GFF   } from '../modules/nf-core/pigz/uncompress/main'
include { GENOME                              } from '../subworkflows/local/genome'
include { GENOME_AND_ANNOTATION               } from '../subworkflows/local/genome_and_annotation'
include { MULTIQC                             } from '../modules/nf-core/multiqc/main'
include { TREE_SUMMARY                        } from '../modules/local/tree_summary'
include { paramsSummaryMap                    } from 'plugin/nf-validation'
include { paramsSummaryMultiqc                } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML              } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText              } from '../subworkflows/local/utils_nfcore_genomeqc_pipeline'
include { validateInputSamplesheet            } from '../subworkflows/local/utils_nfcore_genomeqc_pipeline'
include { FASTA_EXPLORE_SEARCH_PLOT_TIDK      } from '../subworkflows/nf-core/fasta_explore_search_plot_tidk/main'
inclcude {decontamination                     } from '../../subworkflows/local/decontamination'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow GENOMEQC {

    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()
    ch_tree_data = Channel.empty()

    ch_samplesheet
        .map {
            validateInputSamplesheet(it) // Input validation (check local subworkflow)
        }
        .branch {
            ncbi: it.size() == 2
            local: it.size() == 3
        }
        .set { ch_input }

    //
    // MODULE: Run create_path
    //

    CREATE_PATH (
        ch_input.ncbi
    )

    //
    // MODULE: Run ncbigenomedownlaod
    //

    NCBIGENOMEDOWNLOAD ( 
        CREATE_PATH.out.meta,
        CREATE_PATH.out.accession,
        [],
        params.groups
    )
    ch_versions = ch_versions.mix(NCBIGENOMEDOWNLOAD.out.versions.first())
    
    //
    // Define gff and fasta varliables
    //

    fasta = NCBIGENOMEDOWNLOAD.out.fna.mix( ch_input.local.map { [it[0],file(it[2])] } )
    gff   = NCBIGENOMEDOWNLOAD.out.gff.mix( ch_input.local.map { [it[0],file(it[1])] } )
    
    // Uncompress files if necessary | Consider using brances as an alternative

    if (fasta.map { it[1].endsWith(".gz") } ) {
        ch_fasta = UNCOMPRESS_FASTA ( fasta ).file
    } else {
        ch_fasta = fasta
    }
    
    // Uncompress gff if necessary

    if (gff.map { it[1].endsWith(".gz") } ) {
        ch_gff = UNCOMPRESS_GFF ( gff ).file
    } else {
        ch_gff = gff
    }

    //
    // Run TIDK
    //

    FASTA_EXPLORE_SEARCH_PLOT_TIDK (
        ch_fasta,
        []
    )

    // Run genome only or genome + gff


    if (params.genome_only) {
        GENOME (
            ch_fasta
        )
    } else {
        GENOME_AND_ANNOTATION (
            ch_fasta,
            ch_gff
        )
    }

    //
    // MODULE: Run TREE SUMMARY
    //  

    TREE_SUMMARY (
        GENOME_AND_ANNOTATION.out.orthofinder,
        GENOME_AND_ANNOTATION.out.tree_data
    )


    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }





    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))

    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList()
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
