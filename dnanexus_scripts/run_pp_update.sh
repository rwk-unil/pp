#!/bin/bash

if ! command -v realpath &> /dev/null
then
    realpath() {
        [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
    }
fi

if ! command -v jq &> /dev/null
then
    echo "Please install jq"
    echo "E.g., sudo apt install jq"
    exit 1
fi

dx_id_to_path () {
    FFNAME=$(dx describe --json "$1" | jq -r '.name')
    FFPATH=$(dx describe --json "$1" | jq -r '.folder')
    echo "/mnt/project/${FFPATH}/${FFNAME}"
}

# Get the path of this script
SCRIPTPATH=$(realpath  $(dirname "$0"))

VCF_ID=""
BIN_ID=""
OFNAME=""
VERBOSE=""
COST_LIMIT=""
INSTANCE="mem2_ssd1_v2_x2"
DESTINATION="phasing_rare"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

# Command line argument parsing from :
# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
case $key in
    -f|--vcf-id)
    VCF_ID="$2"
    shift # past argument
    shift # past value
    ;;
    -b|--bin-id)
    BIN_ID="$2"
    shift # past argument
    shift # past value
    ;;
    -o|--output)
    OFNAME="$2"
    shift # past argument
    shift # past value
    ;;
    --cost-limit)
    COST_LIMIT="$2"
    shift # past argument
    shift # past value
    ;;
    --instance)
    INSTANCE="$2"
    shift # past argument
    shift # past value
    ;;
    --verbose)
    VERBOSE="-v"
    shift # no value attached
    ;;
    -d|--destination)
    DESTINATION="$2"
    shift
    shift
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ -z "${VCF_ID}" ]
then
    echo "Specify an input BCF ID with --vcf-id <actual_input_id>"
    echo "This is the original VCF/BCF file to be rephased"
    exit 1
fi
if [ -z "${BIN_ID}" ]
then
    echo "Specify an input binary file ID with --bin-id <actual_input_id>"
    echo "This file must be generated from the VCF passed"
    exit 1
fi

VCF_FILENAME=$(dx_id_to_path "${VCF_ID}")
CHROMOSOME=$(basename $(dx describe --json "${VCF_ID}" | jq -r '.folder'))
echo "VCF_FILENAME    = ${VCF_FILENAME}"
echo "CHROMOSOME      = ${CHROMOSOME}"
BIN_FILENAME=$(dx_id_to_path "${BIN_ID}")
echo "BIN FILENAME    = ${BIN_FILENAME}"

if [ -z "${VCF_FILENAME}" ]
then
    echo "Cannot get filename..."
    exit 1
fi

tag=pp_update_v1.2
echo "dx run with tag : ${tag}"

NEW_VCF_FILE="$(basename ${VCF_FILENAME})_rephased.bcf"
if [ -z "${OFNAME}" ]
then
    OFNAME="${NEW_VCF_FILE}"
fi

command="time pp_update -f ${VCF_FILENAME} -o ${OFNAME} -b ${BIN_FILENAME} ${VERBOSE}"

echo "Command : ${command}"
echo "Output file destination : ${DESTINATION}"
echo "Instance type : ${INSTANCE}"

while true; do
    read -p "Do you want to launch on DNANexus? [y/n]" yn
    case $yn in
        y)
        echo "Launching !";
        break
        ;;
        n)
        echo "exiting...";
        exit
        ;;
        *)
        echo "unexpected input"
        ;;
    esac
done

COST_LIMIT_ARG=""
if ! [ -z "${COST_LIMIT}" ]
then
    COST_LIMIT_ARG="--cost-limit ${COST_LIMIT}"
fi

dx run swiss-army-knife -icmd="${command}; bcftools index ${OFNAME}" \
    ${COST_LIMIT_ARG} --name UpdatePhase \
    -iimage_file=docker/pp_rephase_v1.2.tar.gz --tag "${tag}" \
    --destination "${DESTINATION}/rephased/${CHROMOSOME}" \
    --instance-type "${INSTANCE}" -y