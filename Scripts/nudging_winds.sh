#!/bin/bash
# ^specify bash as interpreter

# Copied from slf_and_inp.sh by Jonah Shaw 23/12/19
# Nudging winds to look for slf change from INP forcing

############
# FUNCTIONS
############

# Search and replace function
function ponyfyer() {
    local search=$1 ;
    local replace=$2 ;
    local loc=$3 ;
    # Note the double quotes
    sed -i "s/${search}/${replace}/g" ${loc} ;
}

############
# SET INPUT ARGS
############

args=("$@")
CASENAME=${args[0]}  # uniquecasename, maybe add a timestamp in the python script
wbf=${args[1]}          # wbf multiplier
inp=${args[2]}          # inp multiplier

#echo ${args[0]} ${args[1]} ${args[2]}

############
# SET CASE PARAMETERS
############

models=("noresm-dev" "cesm" "noresm-dev-10072019")
compsets=("NF2000climo" "N1850OCBDRDDMS" "NFAMIPNUDGEPTAEROCLB")
resolutions=("f19_tn14" "f10_f10_mg37", 'f19_g16')
machines=('fram')
projects=('nn9600k')

# Where ./create_case is called from: (do I need a tilde here for simplicity?)
ModelRoot=/cluster/home/jonahks/p/jonahks/models/${models[0]}/cime/scripts

# Where the case it setup, and user_nl files are stored
CASEROOT=/cluster/home/jonahks/p/jonahks/cases

# Where FORTRAN files contains microphysics modifications are stored
ModSource=/cluster/home/jonahks/git_repos/noresm2_mpc/SourceMods

# Set indices to select from arrays here
COMPSET=${compsets[0]}
RES=${resolutions[0]}
MACH=${machines[0]}
PROJECT=${projects[0]}
MISC=--run-unsupported

NUMNODES=-4 # How many nodes each component should run on

echo ${CASEROOT}/${CASENAME} ${COMPSET} ${RES} ${MACH} ${PROJECT} $MISC

#############
# Main Script
#############

cd ${ModelRoot} # Move to appropriate directory
#pwd

# Create env_*.xml files
./create_newcase --case ${CASEROOT}/${CASENAME} \
                 --compset ${COMPSET} \
                 --res ${RES} \
                 --mach ${MACH} \
                 --project ${PROJECT} \
                 $MISC

cd ${CASEROOT}/${CASENAME} # Move to the case's dir

# Set run time and restart variables within env_run.xml
#./xmlchange --file=env_run.xml RESUBMIT=3
./xmlchange STOP_OPTION='nmonth',STOP_N='15' --file env_run.xml
./xmlchange JOB_WALLCLOCK_TIME=06:59:00 --file env_batch.xml --subgroup case.run
# ./xmlchange --file=env_run.xml REST_OPTION=nyears
#./xmlchange --file=env_run.xml REST_N=5
./xmlchange --append CAM_CONFIG_OPTS='-cosp' --file env_build.xml

### Nudging changes
./xmlchange --append CAM_CONFIG_OPTS='--offline_dyn' --file env_build.xml
./xmlchange CALENDAR='GREGORIAN' --file env_build.xml 
./xmlchange RUN_STARTDATE='2000-01-01' --file env_run.xml
# Not sure if this is necessary
cp /cluster/home/jonahks/p/jonahks/models/noresm-dev/components/cam/src/NorESM/fv/metdata.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam

# Makes sure it goes on the development queue
./xmlchange NTASKS=${NUMNODES},NTASKS_ESP=1 --file env_mach_pes.xml

# Move modified WBF process into SourceMods dir:
cp ${ModSource}/micro_mg_cam.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam
cp ${ModSource}/micro_mg2_0.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam

# Move modified INP nucleation process into SourceMods dir:
cp ${ModSource}/hetfrz_classnuc_oslo.F90 /${CASEROOT}/${CASENAME}/SourceMods/src.cam

# Now use ponyfyer to set the values within the sourcemod files. Ex:
mg2_path=/${CASEROOT}/${CASENAME}/SourceMods/src.cam/micro_mg2_0.F90
inp_path=/${CASEROOT}/${CASENAME}/SourceMods/src.cam/hetfrz_classnuc_oslo.F90

ponyfyer 'wbf_tag = 1.' "wbf_tag = ${wbf}" ${mg2_path}
ponyfyer 'inp_tag = 1.' "inp_tag = ${inp}" ${inp_path}

# Set up case, creating user_nl_* files
./case.setup

# Will need to modify the nl files appropriately here to choose output
# CAM adjustments, I don't entirely understand the syntax here, but all the formatting after the first line is totally preserved:
# list variables to add to first history file here
#&aerosol_nl  # Not sure what this is.
# , 'SLFXCLD_ISOTM', 'SADLIQXCLD_ISOTM', 'SADICEXCLD_ISOTM', 'BERGOXCLD_ISOTM',
# 'BERGSOXCLD_ISOTM', 'CLD_ISOTM', 'CLDTAU', 'CLD_SLF', 'CLD_ISOTM_SLF',

# Add additional outputs to the primary history file.
cat <<TXT2 >> user_nl_cam
fincl1 = 'BERGO', 'BERGSO', 'MNUCCTO', 'MNUCCRO', 'MNUCCCO', 'MNUCCDOhet', 'MNUCCDO'
         'DSTFREZIMM', 'DSTFREZCNT', 'DSTFREZDEP', 'BCFREZIMM', 'BCFREZCNT', 'BCFREZDEP',
         'NUMICE10s', 'NUMICE10sDST', 'NUMICE10sBC',
         'dc_num', 'dst1_num', 'dst3_num', 'bc_c1_num', 'dst_c1_num', 'dst_c3_num',
         'bc_num_scaled', 'dst1_num_scaled', 'dst3_num_scaled'
TXT2

# user_nl_cam additions related to nudging. Specify winds, set relax time, set first wind field file, path to all windfield files
# The f16_g16 resolution only has ERA data from 1999-01-01 to 2003-07-14
# Setting drydep_method resolves an error that arises when using the NF2000climo compset
cat <<TXT3 >> user_nl_cam
&metdata_nl
 met_nudge_only_uvps = .true.
 met_data_file='/cluster/shared/noresm/inputdata/noresm-only/inputForNudging/ERA_f19_g16/2000-01-01.nc'
 met_filenames_list = '/cluster/shared/noresm/inputdata/noresm-only/inputForNudging/ERA_f19_g16/fileList3.txt'
 met_rlx_top = 6
 met_rlx_bot = 6
 met_rlx_bot_top = 6
 met_rlx_bot_bot = 6  
 met_rlx_time = 6
 drydep_method = 'xactive_atm'
TXT3

#nhtfrq(1) = 0

exit 1

# build, create *_in files under run/
./case.build

exit 1

# Submit the case
./case.submit
