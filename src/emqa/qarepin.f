
        SUBROUTINE QAREPIN( RCNT, IOS )

C***********************************************************************
C  subroutine body starts at line 
C
C  DESCRIPTION:
C      The QAREPIN routine compares the settings for the current report and 
C      gives errors and warnings if problems are found.
C
C  PRECONDITIONS REQUIRED:
C    REPCONFIG file is opened
C
C  SUBROUTINES AND FUNCTIONS CALLED:
C
C  REVISION  HISTORY:
C     Created 3/2002 by M Houyoux
C
C***********************************************************************
C  
C Project Title: Sparse Matrix Operator Kernel Emissions (SMOKE) Modeling
C                System
C File: @(#)$Id$
C  
C COPYRIGHT (C) 2002, MCNC Environmental Modeling Center
C All Rights Reserved
C  
C See file COPYRIGHT for conditions of use.
C  
C Environmental Modeling Center
C MCNC
C P.O. Box 12889
C Research Triangle Park, NC  27709-2889
C  
C smoke@emc.mcnc.org
C  
C Pathname: $Source$
C Last updated: $Date$ 
C  
C***********************************************************************

C...........   MODULES for public variables
C.........  This module contains Smkreport-specific settings
        USE MODREPRT

C.........  This module contains report arrays for each output bin
c        USE MODREPBN

C.........  This module contains the arrays for state and county summaries
        USE MODSTCY

C.........  This module contains the information about the source category
        USE MODINFO

        IMPLICIT NONE

C...........   INCLUDES
        INCLUDE 'EMCNST3.EXT'   !  emissions constant parameters
        INCLUDE 'PARMS3.EXT'    !  I/O API parameters
        INCLUDE 'IODECL3.EXT'   !  I/O API function declarations
        INCLUDE 'FDESC3.EXT'    !  I/O API file description data structures.

C...........  EXTERNAL FUNCTIONS and their descriptions:
        CHARACTER*2 CRLF
        INTEGER     SECSDIFF

        EXTERNAL    CRLF, SECSDIFF

C...........   SUBROUTINE ARGUMENTS
        INTEGER, INTENT (IN)  :: RCNT       ! report number
        INTEGER, INTENT (OUT) :: IOS        ! error status

C...........   Other local variables
        INTEGER          I
        INTEGER          JDATE                ! Julian date
        INTEGER          JTIME                ! time

        LOGICAL       :: EFLAG   = .FALSE.  !  true: error found

        CHARACTER*300          MESG         !  message buffer

        CHARACTER*16 :: PROGNAME = 'QAREPIN' ! program name

C***********************************************************************
C   begin body of subroutine QAREPIN

C.........  Initialize output error status
        IOS = 0

C.........  Other checks that could be added to this routine:
C        N: Check units (and that multiple ones aren't specified unless this
C        N:     is supported)

C.........  Checks when population normalization is used...
        IF( RPT_%NORMPOP ) THEN

C.............  Ensure that report is by region of some sort
            IF ( .NOT. RPT_%BYCNRY .AND.
     &           .NOT. RPT_%BYSTAT .AND.
     &           .NOT. RPT_%BYCNTY       ) THEN

                WRITE( MESG,94010 ) BLANK5 // 
     &                 'WARNING: Invalid request for population '//
     &                 'normalization without requesting' // CRLF()//
     &                 BLANK16 // 'by country, by state, or by county. '
     &                 // 'Dropping population normalization.'
                CALL M3MSG2( MESG )

                RPT_%NORMPOP = .FALSE.
                ALLRPT( RCNT )%NORMPOP = .FALSE.

            END IF

C.............  Ensure population is present in COSTCY file.
            IF( .NOT. LSTCYPOP ) THEN
                WRITE( MESG,94010 ) BLANK5 // 
     &                 'WARNING: Invalid request for population '//
     &                 'when population is not present' // CRLF()//
     &                 BLANK16 // 'in COSTCY file. '
     &                 // 'Dropping population normalization.'

                CALL M3MSG2( MESG )

                RPT_%NORMPOP = .FALSE.
                ALLRPT( RCNT )%NORMPOP = .FALSE.

C.............  Compare population year to inventory year.
            ELSE IF( STCYPOPYR .NE. BYEAR ) THEN
                WRITE( MESG,94010 ) BLANK5 // 
     &                 'NOTE: Population year ', STCYPOPYR, 
     &                 'is inconsistent with inventory base year',
     &                 BYEAR
                CALL M3MSG2( MESG )

            END IF

        END IF

C.........  Set ending date and time and number of time steps for report
C.........  When using hourly inputs
        IF( RPT_%USEHOUR ) THEN
            JDATE = SDATE
            JTIME = STIME

C.............  Find ending time
            EDATE = SDATE
            ETIME = STIME
            CALL NEXTIME( EDATE, ETIME, ( NSTEPS-1 ) * TSTEP )

C.............  Compare data end time with output end time
            I = SECSDIFF( EDATE, ETIME, 
     &                    EDATE, RPT_%OUTTIME )

C.............  If reporting time is after data ending time, reset the no.
C               of time steps so that the reporting ends on the previous day
            IF( I .GT. 0 ) THEN
                CALL NEXTIME( EDATE, ETIME, -25 * TSTEP )  
                CALL NEXTIME( EDATE, ETIME, TSTEP )         ! Workaround
                ETIME = RPT_%OUTTIME

                I =  SECSDIFF( SDATE, STIME, EDATE, ETIME )
                RPTNSTEP = I / 3600 + 1

C.............  If reporting time is before data ending time, reset the 
C               number of time steps so that the reporting ends on the 
C               reporting hour
C.............  Also set reporting time steps for reporting time matches
C               ending time.
            ELSE IF( I .LE. 0 ) THEN
                RPTNSTEP = NSTEPS + I / 3600

            END IF

C.............  Print message if time steps have changed
            IF( I .NE. 0 ) THEN
                WRITE( MESG,94010 ) BLANK5 // 
     &                 'WARNING: Resetting number of time steps for ' //
     &                 'report to ', RPTNSTEP, CRLF() // BLANK16 // 
     &                 'to make output hour consistent with ' //
     &                 'reporting time.'
                CALL M3MSG2( MESG )
            END IF

C.........  When not using hourly inputs
        ELSE
            RPTNSTEP = 1
        END IF

        RETURN

C******************  FORMAT  STATEMENTS   ******************************

C...........   Internal buffering formats............ 94xxx

94010   FORMAT( 10( A, :, I10, :, 1X ) )

        END SUBROUTINE QAREPIN
