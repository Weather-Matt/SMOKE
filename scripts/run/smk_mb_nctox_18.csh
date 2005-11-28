#!/bin/csh -f
#
# Version @(#)$Id$
# Path    $Source$
# Date    $Date$
#
# This script sets up needed environment variables for creating future-year
# mobile-source emissions and calls the scripts that run the SMOKE programs. 
#
# Script created by : M. Houyoux, CEP Environmental Modeling Center 
#                     February 2003
#*********************************************************************

## Set Assigns file name
setenv ASSIGNS_FILE $SMKROOT/assigns/ASSIGNS.nctox.cmaq.cb4p25_wtox.us12-nc

## Set future year
setenv FYEAR 2018               # year of future case

## Set source category
setenv SMK_SOURCE    M          # source category to process
setenv MRG_SOURCE    M          # source category to merge
setenv MRG_CTLMAT_MULT ' '      # source category to merge multiplicative controls
setenv MRG_CTLMAT_REAC ' '      # source category to merge reactivity controls

## Set programs to run...

## Time-independent programs
setenv RUN_CNTLMAT   Y          # run control and growth matrix program
setenv RUN_GRWINVEN  Y          # run control and growth application program
setenv RUN_MBSETUP   Y          # run speed/temperature setup program        

## Episode-dependent programs
setenv RUN_PREMOBL   Y          # run temperature processing program
setenv RUN_EMISFAC   Y          # run emission factors program

## Time-dependent programs
setenv RUN_TEMPORAL  Y          # run temporal allocation program
setenv RUN_SMKMERGE  Y          # run merge program

## Quality assurance
setenv RUN_SMKREPORT Y          # run emissions reporting program

## Program-specific controls...

# For Cntlmat
setenv PROJECTION_YN_SPEC   Y   # Y uses year-specific /PROJECTION/ packet data
setenv REACTIVITY_POL       ' ' # pollutant name to use in computing reactivity matrix
setenv XREF_SICOVERSCC      Y   # Y matches sources by SIC before SCC
#      REPORT_DEFAULTS  see "Multiple-program controls" below
#      SMK_AVEDAY_YN    see "Multiple-program controls" below
#      SMK_TMPDIR       set by assigns/set_dirs.scr script

## For Grwinven
setenv SMK_GRWIDAOUT_YN     Y   # Y outputs an IDA-formatted inventory
setenv SMK_GRWORLOUT_YN     N   # Y outputs an ORL-formatted inventory
setenv SMK_GRWSMKOUT_YN     Y   # Y outputs a SMOKE-formatted inventory
setenv SMK_NUM_CTLMAT       1   # number of control/growth matrices

## For Mbsetup
setenv USE_INVSPD_DEFAULT   Y   # Y uses inventory speeds when missing hourly speeds
#      USE_SPEED_PROFILES see "Multiple-program controls" below

## For Premobl
setenv SMK_MAXTEMP          120. # maximum allowable hourly temperature in deg F
setenv SMK_MINTEMP          0.   # minimum allowable hourly temperature in deg F
setenv TVARNAME             TEMPG # temperature variable name in meteorology files
setenv UNIFORM_STIME        -1   # indicates day start time; -1 uses time zones
#      OUTZONE          see "Multiple-program controls" below
#      SMK_METPATH      set by assigns/set_dirs.scr script

## For Emisfac
setenv ADJUST_HR_SPEED      Y   # Y adjusts hourly speeds for freeway ramps
setenv ADJUST_INV_SPEED     Y   # Y adjusts inventory speeds for freeway ramps
setenv M6_FLAT_VMT          Y   # Y uses flat hourly VMT profile when running MOBILE6
setenv MB_HC_TYPE           TOG # name of hydrocarbon pollutant to generate factors for
setenv REPLACE_HUMIDITY     Y   # Y replaces humidity data in MOBILE6 inputs
setenv REPLACE_TEMPERATURES Y   # Y replaces temperature data in MOBILE6 inputs
#      EF_YEAR          set by assigns/set_case.scr script
#      GROUP_TYPE       set to [daily|weekly|monthly|episode] when running Emisfac below
#      SMK_EMISPATH     set by assigns/set_dirs.scr script
#      SMK_M6PATH       set by assigns/set_dirs.scr script
#      SMK_METPATH      set by assigns/set_dirs.scr script
#      SMK_SPDPATH      set by assigns/set_dirs.scr script
#      USE_SPEED_PROFILES see "Multiple-program controls" below

## For Temporal
setenv RENORM_TPROF         Y   # Y normalizes the temporal profiles
setenv UNIFORM_TPROF_YN     N   # Y uses uniform temporal profiles for all sources
setenv ZONE4WM              Y   # Y applies temporal profiles using time zones
#      OUTZONE          see "Multiple-program controls" below
#      REPORT_DEFAULTS  see "Multiple-program controls" below
#      SMK_AVEDAY_YN    see "Multiple-program controls" below
#      SMK_MAXERROR     see "Multiple-program controls" below
#      SMK_MAXWARNING   see "Multiple-program controls" below

## For Smkmerge
setenv MRG_SPCMAT_YN        Y   # Y produces speciated output 
setenv MRG_TEMPORAL_YN      Y   # Y produces temporally allocated output
setenv MRG_GRDOUT_YN        Y   # Y produces a gridded output file
setenv MRG_REPCNY_YN        Y   # Y produces a report of emission totals by county
setenv MRG_REPSTA_YN        Y   # Y produces a report of emission totals by state
setenv MRG_REPCTL_YN        N   # Y separately reports controlled emissions
setenv MRG_GRDOUT_UNIT      moles/s   # units for the gridded output file
setenv MRG_TOTOUT_UNIT      moles/day # units for the state and county reports
setenv MRG_MARKETPEN_YN     N   # Y uses market penetration from reactivity matrices
setenv SMK_REPORT_TIME      230000    # hour for reporting daily emissions
#      SMK_AVEDAY_YN    see "Multiple-program controls" below

## For Smkreport
setenv REPORT_ZERO_VALUES   N   # Y outputs entries with all zero values

## Multiple-program controls
setenv OUTZONE              0   # time zone of output emissions
setenv REPORT_DEFAULTS      N   # Y reports sources that use default cross-reference
setenv SMK_AVEDAY_YN        N   # Y uses average-day emissions instead of annual emissions
setenv SMK_MAXERROR         100 # maximum number of error messages in log file
setenv SMK_MAXWARNING       100 # maximum number of warning messages in log file
setenv USE_SPEED_PROFILES   N   # Y uses hourly speed profiles instead of inventory speeds

## Script settings
setenv SRCABBR              mb.$FYEAR # abbreviation for naming log files
setenv QA_TYPE              all # type of QA to perform [none, all, part1, part2, or custom]
setenv PROMPTFLAG           N   # Y prompts for user input
setenv AUTO_DELETE          Y   # Y automatically deletes I/O API NetCDF output files
setenv AUTO_DELETE_LOG      Y   # Y automatically deletes log files
setenv DEBUGMODE            N   # Y runs program in debugger
setenv DEBUG_EXE            pgdbg # debugger to use when DEBUGMODE = Y

## Assigns file override settings
# setenv SPC_OVERRIDE  cmaq.cb4p25  # chemical mechanism override
setenv YEAR_OVERRIDE        1999    # base year override
setenv INVTABLE_OVERRIDE    invtable_onroad.cb4.010804.txt # inventory table override
# setenv CNTLCASE                   # control case name

##############################################################################

## NOTE: GCNTL file for mobile sources must be in the $MBDAT directory for the
#        base case simulation and should have the names, as follows:
#          Projection only     :  gcntl.$YEAR_$FYEAR.txt,
#          Control only        :  gcntl.$CNTLCASE.txt,
#          Projection & control:  gcntl.$YEAR_$FYEAR_$CNTLCASE.txt,
#        where YEAR is set in the Assigns file and FYEAR and CNTLCASE
#        are set in this script.
#
#        In addition, the MOBILE6 inputs for the case you want to run
#        should all have file names with a .in extension and should
#        be placed in a *directory* named as follows:
#          No control name    : $INVDIR/mobile/m6_$EF_YEAR/
#          With control name  : $INVDIR/mobile/m6_$EFYEAR_$CNTLCASE/
#        where EF_YEAR is either YEAR if SMK_FUTURE_YN = N and is
#        FYEAR if SMK_FUTURE_YN = Y.  The CNTLCASE variable will only
#        be used in the directory name if it is defined.

setenv RUN_PART1 Y
source $ASSIGNS_FILE   # Invoke Assigns file

## Set projection and control matrices to use in Grwinven
#      NOTE: Grwinven setting SMK_NUM_CTLMAT > 1 to use MCMAT02-04
setenv MCMAT01 $MPMAT
# setenv MCMAT02 
# setenv MCMAT03 
# setenv MCMAT04 

## Run Cntlmat and Grwinven
#
if ( $?CNTLCASE ) then
    setenv SRCABBR $SRCABBR.$CNTLCASE 
endif
source cntl_run.csh    # Run programs

## Set up for future-year and/or control processing
#
setenv SMK_FUTURE_YN Y
setenv SMK_CONTROL_YN N
setenv RUN_PART1 N     # Temporarily end part 1 to prevent file deletion
source $ASSIGNS_FILE

## Run QA for new grown inventory
#
setenv RUN_PART1 Y     # Restart part 1
source qa_run.csh      # Run QA for part 1

## Run Mbsetup and Premobl
#
source smk_run.csh     # Run remaining programs for part 1
setenv RUN_PART1 N     # End part 1

## Run Emisfac for cases needed by temperature choices in MVREF file
#
foreach group ( episode )  # can include ( daily weekly monthly episode )
  setenv GROUP_TYPE $group
  source emisfac_run.csh     # Run programs
endif

## Loop through days to run Temporal and Smkmerge 
#
setenv RUN_PART2 Y
setenv RUN_PART4 Y
set cnt = 0
set g_stdate_sav = $G_STDATE      
while ( $cnt < $EPI_NDAY )

   @ cnt = $cnt + $NDAYS
   source $ASSIGNS_FILE   # Invoke Assigns file to set new dates
   source smk_run.csh     # Run programs
   source qa_run.csh      # Run QA for part 2
   setenv G_STDATE_ADVANCE $cnt

end
setenv RUN_PART2 N
setenv RUN_PART4 N
unsetenv G_STDATE_ADVANCE

## Ending of script
#
exit( $status )
