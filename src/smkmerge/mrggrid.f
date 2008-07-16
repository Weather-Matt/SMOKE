
        PROGRAM MRGGRID

C***********************************************************************
C  program body starts at line 
C
C  DESCRIPTION:
C    Program MRGGRID reads 2-D and 3-D I/O API files and merges them
C    into a single 2-D or 3-D file (depending on the inputs)
C    The time period merged is adjusted based on the latest
C    starting file and earliest ending file, unless MRG_DIFF_DAY is
C    set in which case the time period is based on the standard 
C    environment variables. All variables are merged, even if different 
C    variables are in each file.
C
C  PRECONDITIONS REQUIRED:  
C
C  SUBROUTINES AND FUNCTIONS CALLED:
C
C  REVISION  HISTORY:
C    Original by M. Houyoux 4/98
C
C***********************************************************************
C
C Project Title: Sparse Matrix Operator Kernel Emissions (SMOKE) Modeling
C                System
C File: @(#)$Id$
C
C COPYRIGHT (C) 2004, Environmental Modeling for Policy Development
C All Rights Reserved
C 
C Carolina Environmental Program
C University of North Carolina at Chapel Hill
C 137 E. Franklin St., CB# 6116
C Chapel Hill, NC 27599-6116
C 
C smoke@unc.edu
C
C Pathname: $Source$
C Last updated: $Date$ 
C
C***********************************************************************
 
C...........   MODULES for public variables
C.........  This module contains the global variables for the 3-d grid
        USE MODGRID, ONLY: NGRID, NCOLS, NROWS, NLAYS, 
     &                     VGLVS, VGTYP, VGTOP

C.........  This module is required for the FileSetAPI
        USE MODFILESET, ONLY : FILE_INFO, RNAMES, NVARSET, VNAMESET, 
     &                         VUNITSET, VDESCSET

        IMPLICIT NONE
 
C...........   INCLUDES:
        INCLUDE 'EMCNST3.EXT'
        INCLUDE 'PARMS3.EXT'
        INCLUDE 'IODECL3.EXT'
        INCLUDE 'FDESC3.EXT'
        INCLUDE 'SETDECL.EXT'   !  FileSetAPI variables and functions

C...........   EXTERNAL FUNCTIONS
        CHARACTER(2)  CRLF
        LOGICAL       BLKORCMT
        LOGICAL       ENVYN, GETYN
        INTEGER       GETFLINE, GETEFILE
        INTEGER       INDEX1
        INTEGER       LBLANK
        INTEGER       PROMPTFFILE
        CHARACTER(16) PROMPTMFILE
        INTEGER       SEC2TIME
        INTEGER       SECSDIFF
        REAL          STR2REAL
        LOGICAL       CHKREAL

        EXTERNAL CRLF, ENVYN, GETFLINE, GETYN, INDEX1, LBLANK,
     &           PROMPTFFILE, PROMPTMFILE, SEC2TIME, SECSDIFF,
     &           BLKORCMT, STR2REAL, CHKREAL

C.........  LOCAL PARAMETERS and their descriptions:

        CHARACTER(50), PARAMETER :: 
     &  CVSW = '$Name$' ! CVS release tag

C...........   LOCAL VARIABLES and their descriptions:

C...........   Emissions arrays
        REAL, ALLOCATABLE :: E2D ( : )        ! 2-d emissions
        REAL, ALLOCATABLE :: EOUT( :,: )      ! output emissions
        REAL, ALLOCATABLE :: BEFORE_ADJ( : )  ! emissions before factors applied
        REAL, ALLOCATABLE :: AFTER_ADJ ( : )  ! emissions after factors applied
        REAL, ALLOCATABLE :: BEFORE_SPC( : )  ! emissions before factors applied
        REAL, ALLOCATABLE :: AFTER_SPC ( : )  ! emissions after factors applied

C...........   Input file descriptors
        INTEGER,       ALLOCATABLE :: DURATA( : ) ! no. time steps
        INTEGER,       ALLOCATABLE :: NCOLSA( : ) ! no. columns
        INTEGER,       ALLOCATABLE :: NROWSA( : ) ! no. rows
        INTEGER,       ALLOCATABLE :: NVARSA( : ) ! no. variables
        INTEGER,       ALLOCATABLE :: SDATEA( : ) ! start date
        INTEGER,       ALLOCATABLE :: STIMEA( : ) ! start time
        INTEGER,       ALLOCATABLE :: NLAYSA( : ) ! number of layers in the file
        INTEGER,       ALLOCATABLE :: NFILES( : ) ! number of files in each fileset
        CHARACTER(16), ALLOCATABLE :: FNAME ( : ) ! 2-d input file names
        LOGICAL,       ALLOCATABLE :: USEFIRST(:) ! true: use first time step of file
        LOGICAL,       ALLOCATABLE :: LVOUTA( :,: ) ! iff out var in input file
        CHARACTER(16), ALLOCATABLE :: VNAMEA( :,: ) ! variable names
        CHARACTER(16), ALLOCATABLE :: VUNITA( :,: ) ! variable units
        CHARACTER(80), ALLOCATABLE :: VDESCA( :,: ) ! var descrip
        REAL,          ALLOCATABLE :: ADJ_FACTOR( : ) ! adjustment factors
        CHARACTER(16), ALLOCATABLE :: ADJ_LFN( : )    ! Species name
        CHARACTER(16), ALLOCATABLE :: ADJ_SPC( :    ) ! logicalFileName
        CHARACTER(33), ALLOCATABLE :: ADJ_LFNSPC( : ) ! concatenated {logicalFileName}_{Species}
        CHARACTER(16)                 VNAMEP( MXVARS3 ) ! pt variable names
        CHARACTER(16)                 VUNITP( MXVARS3 ) ! pt variable units
        CHARACTER(80)                 VDESCP( MXVARS3 ) ! pt var descrip

C...........   Intermediate output variable arrays
        INTEGER       INDXN ( MXVARS3 ) ! sorting index for OUTIDX
        INTEGER       OUTIDX( MXVARS3 ) ! index to master model species list

        CHARACTER(16) OUTNAM( MXVARS3 ) ! unsorted output variable names
        CHARACTER(16) VUNITU( MXVARS3 ) ! unsorted output variable units
        CHARACTER(80) VDESCU( MXVARS3 ) ! unsorted output variable descriptions

        LOGICAL       LVOUTP( MXVARS3 ) ! iff output var exists in point input

C...........   Logical names and unit numbers

        INTEGER       ADEV            ! unit for logical names list for SEG
        INTEGER       IDEV            ! unit for logical names list for 2d files
        INTEGER       LDEV            ! unit for log file
        INTEGER       RDEV            ! unit for merge report file
        INTEGER       ODEV            ! unit for QA report file
        INTEGER       SDEV            ! unit for overall QA report file
        CHARACTER(16) ONAME           ! Merged output file name
        CHARACTER(16) PNAME           ! Point source input file name 

C...........   Other local variables 
        INTEGER       ADJ, C, DD, F, I, J, K, L, L1, L2, NL, V, T ! pointers and counters

        INTEGER       DUMMY                      ! dummy value for use with I/O API functions
        INTEGER       EDATE                      ! ending julian date
        INTEGER       ETIME                      ! ending time HHMMSS
        INTEGER    :: G_SDATE = 0                ! start date from environment
        INTEGER    :: G_STIME = 0                ! start time from environment
        INTEGER    :: G_NSTEPS = 1               ! number of time steps from environment
        INTEGER    :: G_TSTEP = 0                ! time step from environment
        INTEGER       ICNTFIL                    ! tmp count of fileset file count  
        INTEGER       IOS                        ! i/o status
        INTEGER       IREC                       ! line number count
        INTEGER       JDATE                      ! iterative julian date
        INTEGER       JTIME                      ! iterative time HHMMSS
        INTEGER       LB                         ! leading blanks counter
        INTEGER       LE                         ! location of end of string
        INTEGER       MXNFIL                     ! max no. of 2-d input files
        INTEGER       MXNFAC                     ! max no. of adjustment factors
        INTEGER       NADJ                       ! no. of adjustment factors
        INTEGER       NFILE                      ! no. of 2-d input files
        INTEGER       NSTEPS                     ! no. of output time steps
        INTEGER       NVOUT                      ! no. of output variables
        INTEGER       RDATE                      ! reference date
        INTEGER       SAVLAYS                    ! number of layers
        INTEGER       SDATE                      ! starting julian date
        INTEGER       SECS                       ! tmp seconds
        INTEGER       SECSMAX                    ! seconds maximum
        INTEGER       SECSMIN                    ! seconds minimum
        INTEGER       STIME                      ! starting time HHMMSS
        INTEGER       STEPS                      ! tmp number of steps
        INTEGER       TIMET                      ! tmp time from seconds
        INTEGER       TSTEP                      ! time step
        INTEGER       VLB                        ! VGLVS3D lower bound 

        REAL       :: FACS = 1.0                 ! adjustment factor 
        REAL          RATIO                      ! ratio 

        CHARACTER(16)  FDESC                     ! tmp file description
        CHARACTER(16)  NAM                       ! tmp file name
        CHARACTER(16)  VNM                       ! tmp variable name
        CHARACTER(33)  LFNSPC                    ! tmp spec and file name
        CHARACTER(256) LINE                      ! input buffer
        CHARACTER(256) MESG                      ! message field
        CHARACTER(80)  NAME1                     ! tmp file name component
        CHARACTER(15)  RPTCOL                    ! single column in report line
        CHARACTER(10)  EFMT                      ! output emissions foamat
        CHARACTER(100) REPFMT                    ! output emissions foamat
        CHARACTER(300) REPFILE                   ! name of report file
        CHARACTER(300) RPTLINE                   ! line of report file
        CHARACTER(16)  SEGMENT( 5 )              ! line parsing arrays

        LOGICAL    :: HEADER  = .FALSE.   ! header line flag
        LOGICAL    :: EFLAG   = .FALSE.   ! error flag
        LOGICAL    :: FIRST3D = .TRUE.    ! true: first 3-d file not yet input
        LOGICAL    :: LFLAG   = .FALSE.   ! true iff 3-d file input
        LOGICAL    :: TFLAG   = .FALSE.   ! true: grid didn't match
        LOGICAL       MRGDIFF             ! true: merge files from different days

        CHARACTER(16) :: PROGNAME = 'MRGGRID' ! program name
C***********************************************************************
C   begin body of program MRGGRID
 
        LDEV = INIT3()
 
C.........  Write out copyright, version, web address, header info, and prompt
C           to continue running the program.
        CALL INITEM( LDEV, CVSW, PROGNAME )

C.........  Read names of input files and open files
        MESG = 'Enter logical name for 2-D AND 3-D GRIDDED INPUTS list'

        IDEV = PROMPTFFILE( MESG, .TRUE., .TRUE.,
     &                      'FILELIST', PROGNAME   )

C........  Write summary of sector specific factor adjustment output
        ODEV = PROMPTFFILE(
     &         'Enter logical name for the MRGGRID QA REPORT file',
     &         .FALSE., .TRUE., 'REPMERGE', PROGNAME )

        MXNFIL = GETFLINE( ODEV, '' )

        CALL GETENV( 'REPMERGE', REPFILE )
        
        OPEN( ODEV,FILE=REPFILE,STATUS='UNKNOWN',POSITION='APPEND')

C.........  Write header line to report     
        IF( MXNFIL == 0 ) THEN
            WRITE( ODEV,93000 ) '# MRGGRID logical file specific QA Report'
            WRITE( ODEV,93000 ) '#COLUMN_TYPES=Int(4)|Varchar(16)|' // 
     &                     'Varchar(16)|Real(8)|Real(8)|Real(8)|Real(8)'
            WRITE( ODEV,93000 ) 'DATE,FileName,Species,Factor,Before,'//
     &                          'After,Ratio'
        END IF

C........  Write summary of overall factor adjustment output by species
        SDEV = PROMPTFFILE(
     &         'Enter logical name for the MRGGRID Overall REPORT file',
     &         .FALSE., .TRUE., 'REPMERGE_SUM', PROGNAME ) 

        MXNFIL = GETFLINE( SDEV, '' )

        CALL GETENV( 'REPMERGE_SUM', REPFILE )
        
        OPEN(SDEV,FILE=REPFILE,STATUS='UNKNOWN',POSITION='APPEND' )

C.........  Write header line to report     
        IF( MXNFIL == 0 ) THEN
            WRITE( SDEV,93000 ) '# MRGGRID Overall Summary Report by Species'
            WRITE( SDEV,93000 ) '#COLUMN_TYPES=Int(4)|Varchar(16)|' //
     &                          'Real(8)|Real(8)|Real(8)'
            WRITE( SDEV,93000 ) 'DATE,Species,Before,After,Ratio'
        END IF

C.........  Get environment variables
        MESG = 'Merge files from different days into single file'
        MRGDIFF = ENVYN( 'MRG_DIFF_DAYS', MESG, .FALSE., IOS )

        IF( MRGDIFF ) THEN        
C.............  Get date and time settings from environment
            CALL GETM3EPI( -1, G_SDATE, G_STIME, G_TSTEP, G_NSTEPS )        
        END IF

C.........  Determine maximum number of input files in file
        MXNFIL = GETFLINE( IDEV, 'List of files to merge' )

C.........  Write message out about MXVARS3
        WRITE( MESG,94010 ) 'Mrggrid compiled with I/O API MXVARS3 =',
     &                      MXVARS3
        CALL M3MSG2( MESG )

C.........  Allocate memory for arrays that just depend on the maximum number
C           of files
        ALLOCATE( NFILES( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'NFILES', PROGNAME )
        ALLOCATE( DURATA( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'DURATA', PROGNAME )
        ALLOCATE( NCOLSA( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'NCOLSA', PROGNAME )
        ALLOCATE( NROWSA( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'NROWSA', PROGNAME )
        ALLOCATE( NLAYSA( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'NLAYSA', PROGNAME )
        ALLOCATE( NVARSA( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'NVARSA', PROGNAME )
        ALLOCATE( SDATEA( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'SDATEA', PROGNAME )
        ALLOCATE( STIMEA( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'STIMEA', PROGNAME )
        ALLOCATE( FNAME( MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'FNAME', PROGNAME )
        ALLOCATE( LVOUTA( MXVARS3,MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'LVOUTA', PROGNAME )
        ALLOCATE( VNAMEA( MXVARS3,MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'VNAMEA', PROGNAME )
        ALLOCATE( VUNITA( MXVARS3,MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'VUNITA', PROGNAME )
        ALLOCATE( VDESCA( MXVARS3,MXNFIL ), STAT=IOS )
        CALL CHECKMEM( IOS, 'VDESCA', PROGNAME )
        
        IF( MRGDIFF ) THEN
            ALLOCATE( USEFIRST( MXNFIL ), STAT=IOS )
            CALL CHECKMEM( IOS, 'USEFIRST', PROGNAME )
        END IF

C.........  Allocate output layer structure
        ALLOCATE( VGLVS( 0:MXLAYS3 ), STAT=IOS )
        CALL CHECKMEM( IOS, 'VGLVS', PROGNAME )
        VGLVS = 0.

C.........  Loop through input files and open them
        F = 0
        IREC = 0
        DO

C.............  Read file names - exit if read is at end of file
            READ( IDEV, 93000, END=27, IOSTAT=IOS ) LINE
            IREC = IREC + 1

            IF ( IOS .NE. 0 ) THEN
                EFLAG = .TRUE.
                WRITE( MESG,94010 ) 
     &              'I/O error', IOS, 
     &              'reading file list at line', IREC
                CALL M3MESG( MESG )
                CYCLE
            END IF

C.............  Skip blank and comment lines
            IF ( BLKORCMT( LINE ) ) CYCLE

            F = F + 1

            IF( F .LE. MXNFIL ) THEN

                LB = LBLANK ( LINE )
                LE = LEN_TRIM( LINE )
                FNAME( F ) = LINE( LB+1:LE )

                IF ( .NOT. OPENSET( FNAME(F), FSREAD3, PROGNAME )) THEN
 
                    MESG = 'Could not open file "' //
     &                     FNAME( F )( 1:LEN_TRIM( FNAME(F) ) )// '".'
                    CALL M3MSG2( MESG )
                    MESG = 'Ending program "MRGGRID".'
                    CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )

                END IF      !  if open3() failed

C.................  Store whether it's a fileset file or not
                I = INDEX1( FNAME(F), MXFILE3, RNAMES )
                NFILES( F ) = SIZE( FILE_INFO( I )%LNAMES )

            END IF

        END DO
27      CONTINUE

        NFILE = F

        IF( NFILE .GT. MXNFIL ) THEN
            WRITE( MESG,94010 )
     &        'INTERNAL ERROR: Dimension mismatch.  Input file count:',
     &        NFILE, 'program allows (MXNFIL):', MXNFIL
            CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )

        ELSEIF( NFILE .EQ. 0 ) THEN
            MESG = 'No input files in list!'
            CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )

        ENDIF

C.........  Get environment variable settings for adjustment factor input file
        CALL ENVSTR( 'ADJ_FACS', MESG, ' ', NAME1 , IOS )

C.........  Determine maximum number of input files in file
        IF( IOS < 0 ) THEN     !  failure to open
            ADEV = IOS
            MXNFAC = 1
            MESG = 'NOTE : No adjustment factors are applied because'//
     &             ' the ADJ_FACS environment variable is not defined' 
            CALL M3MSG2( MESG )

        ELSE
            MESG = 'Enter logical name for a list of adjustment factors'
            ADEV = PROMPTFFILE( MESG,.TRUE.,.TRUE.,'ADJ_FACS',PROGNAME )
            MXNFAC = GETFLINE( ADEV, 'List of adjustment factos' )

        END IF

C.........  Allocate memory for arrays that just depend on the maximum number
C           of adjustment factors in ADJ_FACS input file.
        ALLOCATE( ADJ_LFN( MXNFAC ), STAT=IOS )
        CALL CHECKMEM( IOS, 'ADJ_LFN', PROGNAME )
        ALLOCATE( ADJ_SPC( MXNFAC ), STAT=IOS )
        CALL CHECKMEM( IOS, 'ADJ_SPC', PROGNAME )
        ALLOCATE( ADJ_LFNSPC( MXNFAC ), STAT=IOS )
        CALL CHECKMEM( IOS, 'ADJ_LFNSPC', PROGNAME )
        ALLOCATE( ADJ_FACTOR( MXNFAC ), STAT=IOS )
        CALL CHECKMEM( IOS, 'ADJ_FACTOR', PROGNAME )

        ADJ_SPC = ' '
        ADJ_LFN = ' '
        ADJ_LFNSPC = ' '
        ADJ_FACTOR = 0.0

        IF( ADEV < 0 ) GOTO 30

C.........  Loop through input files and open them
        IREC = 0
        F = 0
        DO
        
C.............  Read file names - exit if read is at end of file
            READ( ADEV, 93000, END = 30, IOSTAT=IOS ) LINE
            IREC = IREC + 1

            IF ( IOS .NE. 0 ) THEN
                EFLAG = .TRUE.
                WRITE( MESG,94010 ) 
     &              'I/O error', IOS, 
     &              'reading adustment factor file at line', IREC
                CALL M3MESG( MESG )
                CYCLE
            END IF

C.............  Skip blank and comment lines
            IF ( BLKORCMT( LINE ) ) CYCLE

C.............  Get line
            CALL PARSLINE( LINE, 3, SEGMENT )

            CALL UPCASE( SEGMENT( 1 ) )   ! species name
            CALL UPCASE( SEGMENT( 2 ) )   ! logical file name

C.............  Search adjustment factor for the current file
            NAM = TRIM( SEGMENT( 2 ) )
            
            L = INDEX1( NAM, NFILE, FNAME )

            IF( .NOT. CHKREAL( SEGMENT( 3 ) ) ) THEN
            IF( L <= 0 .AND. .NOT. HEADER ) THEN
                HEADER = .TRUE.
                CYCLE
            END IF
            END IF

            IF( HEADER ) THEN
            IF( L <= 0 ) THEN
                MESG = 'ERROR: Not found the adjustment factor ' // 
     &                 TRIM(NAM) // ' file in the FILELIST.'
                CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
            ELSE
                F = F + 1

                ADJ_SPC( F ) = TRIM( SEGMENT( 1 ) )
                ADJ_LFN( F ) = TRIM( SEGMENT( 2 ) ) 
                ADJ_LFNSPC( F ) = TRIM( SEGMENT( 1 ) ) // '_' // 
     &                            TRIM( SEGMENT( 2 ) )
                ADJ_FACTOR( F ) = STR2REAL( SEGMENT( 3 ) )

                IF( ADJ_FACTOR( F ) < 0 ) THEN
                    MESG = 'ERROR: Can not apply a negative ' //
     &                  'adjustment factor for the species ' //
     &                  TRIM( ADJ_SPC(F) ) // ' from the ' // 
     &                  TRIM( NAM ) // ' file'
                    CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )

                ELSE IF( ADJ_FACTOR( F ) == 0 ) THEN
                    MESG = 'WARNING: ' // TRIM( ADJ_SPC(F) ) // 
     &                  ' emissions from the ' //TRIM(NAM)// ' file' //
     &                  ' will be zero due to a zero adjustment factor' 
                    CALL M3MSG2( MESG )

                END IF

            END IF
            END IF

        END DO
30      CONTINUE

        IF( ADEV < 0 ) THEN 
            NADJ = 1
        ELSE
            NADJ = F
        END IF

C.........  Duplicate Check of ADJ_FACS file
        DO  F = 1, NADJ
            LFNSPC = ADJ_LFNSPC( F )
            DD = 0
            DO I = 1, NADJ
                IF( LFNSPC == ADJ_LFNSPC( I ) ) DD = DD + 1
            END DO
	    
            IF( DD > 1 ) THEN
                MESG = 'ERROR: Duplicate entries of '// TRIM(ADJ_SPC(F))
     &               // ' species from the ' // TRIM( ADJ_LFN(F) ) // 
     &              ' file in the ADJ_FACS file.' // LFNSPC
                CALL M3MSG2( MESG )
                EFLAG = .TRUE.
            END IF
        ENDDO

C.........  Give error message and end program unsuccessfully
        IF( EFLAG ) THEN
            MESG = 'ERROR: Duplicate entries in the ADJ_FACS file'
            CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
        END IF

C.........  Allocate arrays that will store sector-specific daily/gridded total emissinos
        ALLOCATE( BEFORE_ADJ( NADJ ), STAT=IOS )
        CALL CHECKMEM( IOS, 'BEFORE_ADJ', PROGNAME )
        ALLOCATE( AFTER_ADJ( NADJ ), STAT=IOS )
        CALL CHECKMEM( IOS, 'AFTER_ADJ', PROGNAME )
        BEFORE_ADJ = 0.0
        AFTER_ADJ  = 0.0

C.........  Determine I/O API layer storage lower bound
        VLB = LBOUND( VGLVS3D,1 )

C.........  Get file descriptions and store for all input files
C.........  Loop through 2D input files
        NLAYS = 1
        DO F = 1, NFILE

            NAM = FNAME( F )
            ICNTFIL = ALLFILES
            IF( NFILES( F ) .EQ. 1 ) ICNTFIL = 1   ! send ALLFILES if more than one file, send 1 otherwise
            IF ( .NOT. DESCSET( NAM, ICNTFIL ) ) THEN
                MESG = 'Could not get description of file "'  //
     &                  NAM( 1:LEN_TRIM( NAM ) ) // '"'
                CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
            ELSE
                NROWSA( F ) = NROWS3D
                NCOLSA( F ) = NCOLS3D
                NLAYSA( F ) = NLAYS3D
                NVARSA( F ) = NVARSET
                SDATEA( F ) = SDATE3D
                STIMEA( F ) = STIME3D
                DURATA( F ) = MXREC3D
                
                IF( F == 1 ) TSTEP = TSTEP3D
                
                DO V = 1, NVARSET
                    VNAMEA( V,F ) = VNAMESET( V )
                    VUNITA( V,F ) = VUNITSET( V )
                    VDESCA( V,F ) = VDESCSET( V )
                END DO
            END IF

C.............  Search for adj factor species and logical file in the FILELIST
            J = INDEX1( NAM, NADJ, ADJ_LFN )
            IF( J > 0 ) THEN
                K = INDEX1( ADJ_SPC( J ), NVARSET, VNAMESET )
                IF( K <= 0 ) THEN
                    MESG = 'ERROR: The species ' //TRIM(ADJ_SPC(J))// 
     &                 ' you want to adjust is not available in the ' //
     &                 TRIM(NAM) // ' file'
                    CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
                END IF
            END IF

C.............  Compare all other time steps back to first file.
C.............  They must match exactly.
            IF( TSTEP3D /= TSTEP ) THEN
                EFLAG = .TRUE.
                WRITE( MESG,94010 ) 'ERROR: Time step', TSTEP3D,
     &                 'in file "' // TRIM( NAM ) //
     &                 '" is inconsistent with first file value of',
     &                 TSTEP
                CALL M3MSG2( MESG )
            END IF

C.............  Compare all other grids back to first grid.
C.............  They must match exactly.
            WRITE( FDESC, '(A,I3.3)' ) 'FILE', F
            TFLAG = .FALSE.
            CALL CHKGRID( FDESC, 'GRID', 0, TFLAG )

            IF( TFLAG ) THEN
                EFLAG = .TRUE.
                L = LEN_TRIM( NAM )
                WRITE( MESG,94010 ) 'ERROR: File "' // NAM( 1:L ) //
     &            '" (NX,NY)  : (', NCOLSA( F ), ',', NROWSA( F ), ')'//
     &            CRLF() // BLANK10 // 'is inconsistent with first ' //
     &            'file (NX,NY) : (', NCOLS, ',', NROWS, ')'
                CALL M3MSG2( MESG )
            END IF

C.............  Compare layer structures for 3-d files. The number of layers do 
C               not need to match, but the layer structures do need to match.
            NLAYS = MAX( NLAYS, NLAYSA( F ) )
            IF( NLAYSA( F ) .GT. 1 ) THEN
                LFLAG = .TRUE.

C.................  For the first file that is 3-d, initialize output layer
C                   structure       
                IF ( FIRST3D ) THEN

                    NLAYS = NLAYSA( F )
                    VGTYP = VGTYP3D
                    VGTOP = VGTOP3D
                    VGLVS( 0:NLAYS ) = VGLVS3D( 0+VLB:NLAYS+VLB )   ! array
                    FIRST3D = .FALSE.

C.................  For additional 3-d files, compare the layer structures
                ELSE

C.....................  Check vertical type
                    IF( VGTYP3D .NE. VGTYP ) THEN
                        EFLAG = .TRUE.
                        L = LEN_TRIM( NAM )
                        WRITE( MESG, 94010 ) 'ERROR: Vertical ' //
     &                         'coordinate type', VGTYP3D, 
     &                         'in file "'// NAM(1:L) //
     &                         '" is inconsistent with first 3-d'//
     &                         'file value of', VGTYP
                        CALL M3MSG2( MESG )
                    END IF

C.....................  Check vertical top
                    IF( VGTOP3D .NE. VGTOP ) THEN
                        EFLAG = .TRUE.
                        L = LEN_TRIM( NAM )
                        WRITE( MESG, 94010 ) 'ERROR: Vertical ' //
     &                         'top value', VGTOP3D, 
     &                         'in file "'// NAM(1:L) //
     &                         '" is inconsistent with first 3-d'//
     &                         'file value of', VGTOP
                        CALL M3MSG2( MESG )
                    END IF

C.....................  Loop through layers of current file F
                    DO NL = 0, NLAYSA( F )

C.........................  For layers that are common to this file and previous
C                           files
                        IF( NL .LE. NLAYS ) THEN

                            IF( VGLVS3D( NL+VLB ) .NE. VGLVS( NL )) THEN
                                EFLAG = .TRUE.
                                L = LEN_TRIM( NAM )
                                WRITE( MESG, 94020 ) 'ERROR: Layer', NL,
     &                            'in file "'// NAM( 1:L ) // 
     &                            '" with level value', VGLVS3D(NL+VLB), 
     &                            CRLF()//BLANK10//'is inconsistent '//
     &                            'with first file value of', VGLVS(NL)
                                CALL M3MSG2( MESG )
                            END IF

C.........................  Add additional layers from current file to output 
C                           layer structure
                        ELSE
                            VGLVS( NL ) = VGLVS3D( NL+VLB )
                        END IF

                    END DO    ! End checking layers

C.....................  Reset the global number of layers as the maximum between
C                       the current file and all previous files
                    NLAYS = MAX( NLAYS, NLAYSA( F ) )

                END IF        ! End first 3-d file or not
            END IF            ! End 3-d files

        END DO                ! End loop through files

C.........  Give error message and end program unsuccessfully
        IF( EFLAG ) THEN
            MESG = 'Inconsistent time step, grid, or layers ' //
     &              'among the files!'
            CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
        END IF

C.........  Check that environment settings are consistent with files
        IF( MRGDIFF ) THEN
            IF( TSTEP /= G_TSTEP ) THEN
                WRITE( MESG,94010 ) 'ERROR: Value for G_TSTEP ',
     &              G_TSTEP, 'is inconsistent with the time step' //
     &              CRLF() // BLANK10 // 'of the input files', TSTEP
                CALL M3MSG2( MESG )
                
                MESG = 'Inconsistent environment settings'
                CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
            END IF
        END IF

C.........  Deterimine output date, time, and number of time steps
        SDATE = G_SDATE
        STIME = G_STIME
        NSTEPS = G_NSTEPS
        CALL SETOUTDATE( SDATE, STIME, NSTEPS, NFILE, SDATEA,
     &                   STIMEA, DURATA, FNAME, MRGDIFF, USEFIRST )

C.........  Build master output variables list
        NVOUT = 0

C.........  Loop through input files and build an output variable list
        DO F = 1, NFILE

C.............  Loop through variables in the files
            DO V = 1, NVARSA( F )

                VNM = VNAMEA( V,F )

C.................  Look for variable name in output list
                K = INDEX1( VNM, NVOUT, OUTNAM  )  ! look in output list

C.................  If its not in the output list, add it
                IF( K .LE. 0 ) THEN
                    NVOUT = NVOUT + 1
                    INDXN ( NVOUT ) = NVOUT
                    OUTNAM( NVOUT ) = VNM
                    VDESCU( NVOUT ) = VDESCA( V,F )
                    VUNITU( NVOUT ) = VUNITA( V,F )

C.................  If variable is in the output list, check the units
                ELSE
                    IF ( VUNITA( V,F ) .NE. VUNITU( K ) ) THEN
                        EFLAG = .TRUE.
                        L  = LEN_TRIM( VNM )
                        L1 = LEN_TRIM( VUNITA( V,F ) )
                        L2 = LEN_TRIM( VUNITU( K )   )
                        WRITE( MESG,94010 ) 'ERROR: Variable "' //
     &                         VNM( 1:L ) // '" in file', F,
     &                         'has units "'// VUNITA( V,F )( 1:L1 ) //
     &                         '"' // CRLF() // BLANK10 //
     &                         'that are inconsistent with a '//
     &                         'previous file that had units "' //
     &                         VUNITU(K)( 1:L2 )// '" for this variable'
                        CALL M3MSG2( MESG )

                    END IF  ! End check of units

                END IF      ! End variable in output list already or not

            END DO          ! End loop through variables in this file
        END DO              ! End loop through files.

C.........  Give error message and end program unsuccessfully
        IF( EFLAG ) THEN
            MESG = 'Inconsistent units for common variables among '//
     &             'the files!'
            CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
        END IF

C.........  Sort output variables into alphabetical order
        CALL SORTIC( NVOUT, INDXN, OUTNAM )

C.........  Set up for opening output file...
C.........  Get grid information
        ICNTFIL = ALLFILES
        IF( NFILES( 1 ) .EQ. 1 ) ICNTFIL = 1   ! send ALLFILES if more than one file, send 1 otherwise

        IF( .NOT. DESCSET( FNAME( 1 ), ICNTFIL ) ) THEN
            MESG = 'Could not get description of file "'  //
     &              FNAME( 1 )( 1:LEN_TRIM( FNAME(1) ) ) // '"'
            CALL M3EXIT( PROGNAME, 0, 0, MESG, 2 )
        ENDIF

        SDATE3D = SDATE
        STIME3D = STIME
        NVARS3D = NVOUT

C.........  Set up layer structure for output file
        NLAYS3D = NLAYS
        VGTOP3D = VGTOP
        VGTYP3D = VGTYP
        VGLVS3D = 0.     ! initialize array
        DO NL = 0, NLAYS
            VGLVS3D( NL+VLB ) = VGLVS( NL )
        END DO

C........  Update variable names in sorted order, and also 
C........  set up logical arrays for which files have which species
        DO V = 1, NVOUT
            VNM = OUTNAM( INDXN( V ) )

            VNAME3D( V ) = VNM                  ! store sorted output vars, etc.
            VDESC3D( V ) = VDESCU( INDXN( V ) )
            UNITS3D( V ) = VUNITU( INDXN( V ) )
            VTYPE3D( V ) = M3REAL

            DO F = 1, NFILE
                LVOUTA( V,F ) = .FALSE.

                J = INDEX1( VNM, NVARSA( F ), VNAMEA( 1,F ) )
                IF( J .GT. 0 ) LVOUTA( V,F ) = .TRUE.
                                
            END DO 
        END DO

C.........  Allocate memory for the number of grid cells and layers
        NGRID = NROWS * NCOLS
        ALLOCATE( E2D( NGRID ), STAT=IOS )
        CALL CHECKMEM( IOS, 'E2D', PROGNAME )
        ALLOCATE( EOUT( NGRID, NLAYS ), STAT=IOS )
        CALL CHECKMEM( IOS, 'EOUT', PROGNAME )

C.........  Prompt for and open output file
        ONAME = PROMPTMFILE( 
     &          'Enter logical name for MERGED GRIDDED OUTPUT file',
     &          FSUNKN3, 'OUTFILE', PROGNAME )

C.........  Prompt for and open report file
        IF( MRGDIFF ) THEN
            RDEV = PROMPTFFILE(
     &             'Enter logical name for the MRGGRID REPORT file',
     &             .FALSE., .TRUE., 'REPMRGGRID', PROGNAME ) 

C.............  Write header line to report     
            WRITE( RPTLINE,93010 ) 'Output date'
            WRITE( RPTCOL,93010 ) 'Output time'
            RPTLINE = TRIM( RPTLINE ) // RPTCOL
            
            DO F = 1, NFILE
                NAM = FNAME( F )
                WRITE( RPTCOL,93010 ) TRIM( NAM ) // ' date'
                RPTLINE = TRIM( RPTLINE ) // RPTCOL
            END DO
            
            WRITE( RDEV,93000 ) TRIM( RPTLINE )
        END IF

C.........  Allocate arrays that will store overall daily/gridded total emissinos by species
        ALLOCATE( BEFORE_SPC( NVOUT ), STAT=IOS )
        CALL CHECKMEM( IOS, 'BEFORE_SPC', PROGNAME )
        ALLOCATE( AFTER_SPC( NVOUT ), STAT=IOS )
        CALL CHECKMEM( IOS, 'AFTER_SPC', PROGNAME )
        BEFORE_SPC = 0.0
        AFTER_SPC  = 0.0

C.........  Loop through hours
        JDATE = SDATE
        JTIME = STIME
        FACS  = 1.0
        DO T = 1, NSTEPS

C.............  Loop through species
            DO V = 1, NVOUT

                VNM = VNAME3D( V ) 

C.................  Output array
                EOUT = 0.   ! array

                DO F = 1, NFILE

C.....................  Set read date
                    IF( MRGDIFF ) THEN
                      IF( USEFIRST( F ) ) THEN
                        DUMMY = 0
                        STEPS = SEC2TIME( 
     &                            SECSDIFF( 
     &                              SDATE, DUMMY, JDATE, DUMMY ) )
                        RDATE = SDATEA( F )
                        CALL NEXTIME( RDATE, DUMMY, STEPS )
                      END IF 
                    ELSE
                        RDATE = JDATE
                    END IF

C.....................  Set tmp variables
                    NAM = FNAME ( F )       ! input file name
                    NL  = NLAYSA( F )       ! number of layers

C.....................  Search adjustment factor for the current file
                    LFNSPC = TRIM( VNM ) // '_' // TRIM( NAM )
                    ADJ = INDEX1( LFNSPC, NADJ, ADJ_LFNSPC )

C.....................  Assign adjustment factor for the current species
                    IF( ADJ > 0 ) THEN
                        FACS = ADJ_FACTOR( ADJ )

                        WRITE( MESG,93011 )'Apply adjustment factor' ,
     &                      FACS, ' to the '  // TRIM( VNM ) //
     &                      ' species from the '//TRIM( NAM )// ' file'
                        CALL M3MSG2( MESG )
                    ELSE
                        FACS = 1.0
                        
                    END IF

C.....................  If file has species, read (do this for all files)...
                    IF( LVOUTA( V,F ) ) THEN

                        ICNTFIL = ALLFILES
                        IF( NFILES( F ) .EQ. 1 ) ICNTFIL = 1   ! send ALLFILES if more than one file, send 1 otherwise

C.........................  If 2-d input file, read, and add
                        IF( NL .EQ. 1 ) THEN
                            IF( .NOT. 
     &                           READSET( NAM, VNM, 1, ICNTFIL,
     &                                    RDATE, JTIME, E2D     )) THEN

                                MESG = 'Could not read "' // VNM //
     &                                 '" from file "' //
     &                                 NAM( 1:LEN_TRIM( NAM ) )// '".'
                                CALL M3EXIT( PROGNAME, RDATE, JTIME, 
     &                                       MESG, 2 )
                            ENDIF

C.............................  Logical file specific summary
                            BEFORE_ADJ( ADJ ) = BEFORE_ADJ( ADJ ) + 
     &                                        SUM( E2D(1:NGRID) )

                            AFTER_ADJ ( ADJ ) = AFTER_ADJ ( ADJ ) + 
     &                                        SUM( E2D(1:NGRID)*FACS )

                            BEFORE_SPC( V )  = BEFORE_SPC( V ) + 
     &                                        SUM( E2D(1:NGRID) )

C.............................  Overall summary by species
                            AFTER_SPC ( V ) = AFTER_SPC ( V ) + 
     &                                        SUM( E2D(1:NGRID)*FACS )

                            EOUT( 1:NGRID,1 ) = EOUT( 1:NGRID,1 ) + 
     &                                          E2D( 1:NGRID) * FACS

C.........................  If 3-d input file, allocate memory, read, and add
                        ELSE

                            DO K = 1, NL
                                IF( .NOT. 
     &                               READSET( NAM,VNM,K,ICNTFIL,
     &                                        RDATE, JTIME, E2D  )) THEN

                                    MESG = 'Could not read "' // VNM //
     &                                     '" from file "' //
     &                                   NAM( 1:LEN_TRIM( NAM ) )// '".'
                                    CALL M3EXIT( PROGNAME, RDATE, JTIME,
     &                                           MESG, 2 )
                                END IF

C.................................  Logical file specific summary
                                BEFORE_ADJ( ADJ ) = BEFORE_ADJ( ADJ ) + 
     &                                            SUM( E2D(1:NGRID) )

                                AFTER_ADJ ( ADJ ) = AFTER_ADJ ( ADJ ) + 
     &                                            SUM(E2D(1:NGRID)*FACS)

C.................................  Overall summary by species
                                BEFORE_SPC( V )  = BEFORE_SPC( V ) + 
     &                                           SUM( E2D(1:NGRID) )

                                AFTER_SPC ( V ) = AFTER_SPC ( V ) + 
     &                                            SUM(E2D(1:NGRID)*FACS)

                                EOUT( 1:NGRID,K )= EOUT( 1:NGRID,K ) + 
     &                                             E2D( 1:NGRID )*FACS
                            END DO

                        END IF  ! if 2-d or 3-d
                    END IF      ! if pollutant is in this file

C.....................  Build report line if needed
                    IF( MRGDIFF .AND. V == 1 ) THEN
                        IF( F == 1 ) THEN
                            WRITE( RPTLINE,93020 ) JDATE
                            WRITE( RPTCOL,93020 ) JTIME
                            RPTLINE = TRIM( RPTLINE ) // RPTCOL
                        END IF
                        
                        WRITE( RPTCOL,93020 ) RDATE
                        RPTLINE = TRIM( RPTLINE ) // RPTCOL
                    END IF

                END DO          ! loop over input files

C.................  Write species/hour to output file
                IF( .NOT. WRITE3( ONAME, VNM, JDATE, JTIME, EOUT )) THEN

                    MESG = 'Could not write "'// VNM// '" to file "'// 
     &                      ONAME( 1:LEN_TRIM( ONAME ) ) // '".'
     &                        
                    CALL M3EXIT( PROGNAME, JDATE, JTIME, MESG, 2 )

                END IF

            END DO   ! loop through variables

C.............  Write this time step to report
            IF( MRGDIFF ) THEN
                WRITE( RDEV,93000 ) TRIM( RPTLINE )
            END IF

            CALL NEXTIME( JDATE, JTIME, TSTEP )
      
        END DO       ! loop through timesteps

        WRITE( RDEV,93000 ) TRIM( RPTLINE )

C........  Write summary of sector specific factor adjustment output
C          Columns: Date, Sector, Species, value before, value after, ratio of before/after
C          Later we can add the total amount of the adjusted species summed accross all of the input files
C          and the total amount of the adjusted species in the output file.

C.........  Write header line to report     
        DO F = 1, NADJ

            VNM = ADJ_SPC( F )     ! species name
            NAM = ADJ_LFN( F )     ! logical file name
            FACS   = ADJ_FACTOR( F )   ! adjustment factor
            LFNSPC = ADJ_LFNSPC( F )
            RATIO = ( AFTER_ADJ( F ) / BEFORE_ADJ( F ) )

            IF( BEFORE_ADJ( F ) == 0.0 ) CYCLE

            REPFMT = "(I8,2(',',A),',',F10.3,',',"

C.............  Define the format of real values
            CALL GET_FORMAT( VNM, BEFORE_ADJ( F ), EFMT )
            REPFMT = TRIM( REPFMT ) // TRIM( EFMT )

            CALL GET_FORMAT( VNM, AFTER_ADJ( F ), EFMT )
            REPFMT = TRIM( REPFMT ) // TRIM( EFMT )
            REPFMT = TRIM( REPFMT ) // "F10.3)"

            WRITE( RPTLINE,REPFMT ) SDATE, NAM, VNM, FACS,
     &                            BEFORE_ADJ( F ), AFTER_ADJ( F ), RATIO

            IF( RATIO /= 1.0 ) WRITE( ODEV,93000 ) TRIM( RPTLINE )
        END DO

        CLOSE(ODEV)

C.........  Write header line to overall summary report     
        DO V = 1, NVOUT

            VNM   = VNAME3D( V )     ! species name
            RATIO = ( AFTER_SPC( V ) / BEFORE_SPC( V ) )

            IF( BEFORE_SPC( V ) == 0.0 ) CYCLE

            REPFMT = "( I8,',',A,',',"

C.............  Define the format of real values
            CALL GET_FORMAT( VNM, BEFORE_SPC( V ), EFMT )
            REPFMT = TRIM( REPFMT ) // TRIM( EFMT )

            CALL GET_FORMAT( VNM, AFTER_SPC( V ), EFMT )
            REPFMT = TRIM( REPFMT ) // TRIM( EFMT )
            REPFMT = TRIM( REPFMT ) // "F10.3)"

            WRITE( RPTLINE,REPFMT ) SDATE, VNM, BEFORE_SPC(V),
     &                              AFTER_SPC(V),RATIO

            IF( RATIO /= 1.0 ) WRITE( SDEV,93000 ) TRIM( RPTLINE )

        END DO

        CLOSE( SDEV )

C......... Normal Completion
        CALL M3EXIT( PROGNAME, 0, 0, ' ', 0)
    
C******************  FORMAT  STATEMENTS   ******************************

C...........   Informational (LOG) message formats... 92xxx

92000   FORMAT( 5X, A )
 
C...........   Formatted file I/O formats............ 93xxx

93000   FORMAT(  A )

93010   FORMAT( A15 )

93011   FORMAT(  A, F8.5, A )

93020   FORMAT( I15 )

C...........   Internal buffering formats............ 94xxx

94010   FORMAT( 10( A, :, I7, :, 1X ) )

94020   FORMAT( A, :, I3, :, 1X, 10 ( A, :, F8.5, :, 1X ) )


C*****************  INTERNAL SUBPROGRAMS  ******************************

        CONTAINS

C----------------------------------------------------------------------

C.............  This internal subprogram determines the format to output
C               emission values
            SUBROUTINE GET_FORMAT( VBUF, VAL, FMT )

C.............  Subroutine arguments
            CHARACTER(*), INTENT (IN) :: VBUF
            REAL        , INTENT (IN) :: VAL
            CHARACTER(*), INTENT(OUT) :: FMT

C----------------------------------------------------------------------

C.............  Value is too large for 
            IF( VAL .GT. 999999999. ) THEN
                FMT = "E10.3,',',"

                L = LEN_TRIM( VBUF )
                WRITE( MESG,95020 ) 'WARNING: "' // VBUF( 1:L ) // 
     &              '"Emissions value of', VAL, CRLF()// BLANK10// 
     &              '" is too large for file format, so writing ' //
     &              'in scientific notation for source'

                CALL M3MESG( MESG )

            ELSE IF( VAL .GT. 99999999. ) THEN
                FMT = "F10.0,',',"

            ELSE IF( VAL .GT. 9999999. ) THEN
                FMT = "F10.1,',',"

            ELSE IF( VAL .GT. 999999. ) THEN
                FMT = "F10.2,',',"

            ELSE IF( VAL .GT. 0. .AND. VAL .LT. 1. ) THEN
                FMT = "E10.4,',',"

            ELSE
                FMT = "F10.3,',',"

            END IF

            RETURN

95020       FORMAT( 10( A, :, E12.5, :, 1X ) )

            END SUBROUTINE GET_FORMAT

        END PROGRAM MRGGRID
