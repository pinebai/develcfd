!> \file: InitMultiBlock.F90
!> \author: Sayop Kim

MODULE InitMultiBlock_m
   USE Parameters_m, ONLY: wp
#ifndef SERIAL
   USE GlobalVars_m, ONLY: MPI_COMM_WORLD, rank, blkInThisRank
#else
   USE GlobalVars_m, ONLY: rank
#endif

CONTAINS


!-----------------------------------------------------------------------------!
   SUBROUTINE ReadNODEfiles(blk, nbp, ngc)
!-----------------------------------------------------------------------------!
      USE MultiBlockVars_m, ONLY: MultiBlock

      IMPLICIT NONE
      TYPE(MultiBlock), DIMENSION(:), INTENT(INOUT) :: blk
      INTEGER, INTENT(IN) :: nbp, ngc
      INTEGER :: n, iblk, nneighbor, intDUMP, nID
      INTEGER :: i, j, k, ierr
      CHARACTER(LEN=128) :: NODEFILE, charDUMP

      IF (rank .EQ. 0) THEN
         WRITE(*,*) ''
         WRITE(*,*) '# Reading NODE files.'
      END IF

#ifndef SERIAL
      CALL MPI_BARRIER(MPI_COMM_WORLD, ierr)
#endif

      DO iblk = 1, nbp
#ifndef SERIAL
         WRITE(NODEFILE,'("NODE_",I5.5,".DATA")') blkInThisRank(iblk)
#else
         WRITE(NODEFILE,'("NODE_",I5.5,".DATA")') iblk
#endif
         OPEN(30, FILE = NODEFILE, FORM = "FORMATTED")
         READ(30,'(A20,I6)') charDUMP, blk(iblk)%domainID
         READ(30,'(A20,I6)') charDUMP, intDUMP
#ifndef SERIAL
         IF (blkInThisRank(iblk) .NE. intDUMP) THEN
#else
         IF (iblk .NE. intDUMP) THEN
#endif
            WRITE(*,*) "---------------------------------------------------"
            WRITE(*,*) 'WARNING: blockID is incorrect in ', NODEFILE
            WRITE(*,*) "---------------------------------------------------"
            STOP
         END IF
#ifndef SERIAL
         CALL MPI_BARRIER(MPI_COMM_WORLD, ierr)
#endif

         READ(30,'(A20,I6)') charDUMP, nneighbor
         READ(30,'(A20,I6)') charDUMP, intDUMP
         IF (ngc .NE. intDUMP) THEN
            WRITE(*,*) "--------------------------------------------------------------&
                        -----------------"
            WRITE(*,*) "WARNING: NUMBER OF LEVELS does NOT match 'ngc' in input file: ", &
                        NODEFILE
            WRITE(*,*) "--------------------------------------------------------------&
                        -----------------"
            STOP
         END IF
#ifndef SERIAL
         CALL MPI_BARRIER(MPI_COMM_WORLD, ierr)
#endif

         READ(30,*) charDUMP
         READ(30,*) blk(iblk)%istart, blk(iblk)%iend, &
                    blk(iblk)%jstart, blk(iblk)%jend, &
                    blk(iblk)%kstart, blk(iblk)%kend

         !> Define block size based on the NODE files
         blk(iblk)%imin = blk(iblk)%istart - ngc
         blk(iblk)%imax = blk(iblk)%iend   + ngc
         blk(iblk)%jmin = blk(iblk)%jstart - ngc
         blk(iblk)%jmax = blk(iblk)%jend   + ngc
         blk(iblk)%kmin = blk(iblk)%kstart - ngc
         blk(iblk)%kmax = blk(iblk)%kend   + ngc

         blk(iblk)%isize = blk(iblk)%imax - blk(iblk)%imin + 1
         blk(iblk)%jsize = blk(iblk)%jmax - blk(iblk)%jmin + 1
         blk(iblk)%ksize = blk(iblk)%kmax - blk(iblk)%kmin + 1


         blk(iblk)%neighbor = 0
         DO n = 1, nneighbor
            READ(30,'(A12,I6)') charDUMP, nID
            READ(30,'(A12,3I5)') charDUMP, i, j, k
            blk(iblk)%neighbor(i,j,k) = nID
         END DO
         CLOSE(30)
      END DO

   END SUBROUTINE


!-----------------------------------------------------------------------------!
   SUBROUTINE ReadStructuredGrid(blk, nblk, ngc)
!-----------------------------------------------------------------------------!
      USE MultiBlockVars_m, ONLY: MultiBlock, AllocateMultiBlockXYZ

      IMPLICIT NONE
      !> nblk: number of blocks read from input file
      !> nblocks: number of blocks read from grid file
      TYPE(MultiBlock), DIMENSION(:), INTENT(INOUT) :: blk
      INTEGER, INTENT(IN) :: nblk, ngc
      INTEGER :: nblocks
      INTEGER :: i, j, k
      INTEGER :: isize, jsize, ksize
      INTEGER :: n, iblk
      INTEGER, DIMENSION(:), ALLOCATABLE :: ni, nj, nk
      REAL, DIMENSION(:,:,:,:), ALLOCATABLE :: x, y, z
      CHARACTER(LEN=128) :: GRIDFILE

      GRIDFILE = 'GRID.DATA'
      IF (rank .EQ. 0) THEN
         WRITE(*,*) ''
         WRITE(*,*) '# Reading a structured grid: ', GRIDFILE
      END IF

      OPEN(10, FILE = GRIDFILE, FORM = "FORMATTED")
      READ(10,*) nblocks
      IF (nblocks .NE. nblk) THEN
         WRITE(*,*) 'WARNING: Please check "nblk" in input file.'
         WRITE(*,*) 'The number of blocks read from grid is NOT equal to "nblk".'
         STOP
      END IF

      ALLOCATE(ni(nblk))
      ALLOCATE(nj(nblk))
      ALLOCATE(nk(nblk))

      !> Read block size
      DO iblk = 1, nblk
         READ(10,*) isize, jsize, ksize
         !> Check whether the block size read from the grid files
         !> match the sizes from NODE files
         IF ((isize .NE. blk(iblk)%isize) .OR. &
             (jsize .NE. blk(iblk)%jsize) .OR. &
             (ksize .NE. blk(iblk)%ksize)) THEN
            WRITE(*,*) '---------------------------------------------&
                        --------------------------------------------'
            WRITE(*,*) 'Block size from the grid file does NOT match &
                        the size from the NODE file in block ID: ', iblk
            WRITE(*,*) '---------------------------------------------&
                        --------------------------------------------'
            STOP
         END IF

         CALL AllocateMultiBlockXYZ(blk(iblk), blk(iblk)%imin, blk(iblk)%imax, &
                                               blk(iblk)%jmin, blk(iblk)%jmax, &
                                               blk(iblk)%kmin, blk(iblk)%kmax)

      END DO

      !> Read node point coordinates
      DO iblk = 1, nblk
         READ(10,*) &
         (((blk(iblk)%x(i,j,k), i=blk(iblk)%imin, blk(iblk)%imax), &
                                j=blk(iblk)%jmin, blk(iblk)%jmax), &
                                k=blk(iblk)%kmin, blk(iblk)%kmax), &
         (((blk(iblk)%y(i,j,k), i=blk(iblk)%imin, blk(iblk)%imax), &
                                j=blk(iblk)%jmin, blk(iblk)%jmax), &
                                k=blk(iblk)%kmin, blk(iblk)%kmax), &
         (((blk(iblk)%z(i,j,k), i=blk(iblk)%imin, blk(iblk)%imax), &
                                j=blk(iblk)%jmin, blk(iblk)%jmax), &
                                k=blk(iblk)%kmin, blk(iblk)%kmax)
      END DO
      CLOSE(10)

   END SUBROUTINE


!-----------------------------------------------------------------------------!
   SUBROUTINE ReadBCinfo(nblk, blk)
!-----------------------------------------------------------------------------!
      USE MultiBlockVars_m, ONLY: MultiBlock

      IMPLICIT NONE
      TYPE(MultiBlock), DIMENSION(:), INTENT(INOUT) :: blk
      INTEGER, INTENT(IN) :: nblk
      INTEGER :: iblk, ndump
      CHARACTER(LEN=128) BCFILE

      IF (rank .EQ. 0) THEN
         WRITE(*,*) ""
         WRITE(*,*) '# Reading boundary condition info for structured grid'
      END IF

      BCFILE = 'bcinfo.dat'
      OPEN(10, FILE = BCFILE, FORM = "FORMATTED")
      READ(10,*)

      DO iblk = 1, nblk
         READ(10,*) ndump, blk(iblk)%bc_imin, blk(iblk)%bc_imax, &
                           blk(iblk)%bc_jmin, blk(iblk)%bc_jmax, &
                           blk(iblk)%bc_kmin, blk(iblk)%bc_kmax
      END DO
      CLOSE(10)

   END SUBROUTINE


END MODULE
