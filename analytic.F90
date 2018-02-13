MODULE FTEIK_ANALYTIC64F
  USE ISO_C_BINDING
  USE FTEIK_CONSTANTS64F, ONLY : FTEIK_NATURAL_ORDERING, &
                                 FTEIK_ZXY_ORDERING,     &    
                                 FTEIK_XYZ_ORDERING,     &    
                                 FTEIK_ZYX_ORDERING
  IMPLICIT NONE
  INTEGER(C_INT), PROTECTED, SAVE :: nx = 0    !< Number of grid points in x.
  INTEGER(C_INT), PROTECTED, SAVE :: ny = 0    !< Number of grid points in y.
  INTEGER(C_INT), PROTECTED, SAVE :: nz = 0    !< Number of grid points in z.
  REAL(C_DOUBLE), PROTECTED, SAVE :: dx = 0.d0 !< Grid spacing in x (meters)
  REAL(C_DOUBLE), PROTECTED, SAVE :: dy = 0.d0 !< Grid spacing in y (meters)
  REAL(C_DOUBLE), PROTECTED, SAVE :: dz = 0.d0 !< Grid spacing in z (meters)
  REAL(C_DOUBLE), PROTECTED, SAVE :: x0 = 0.d0 !< x origin (meters).
  REAL(C_DOUBLE), PROTECTED, SAVE :: y0 = 0.d0 !< y origin (meters).
  REAL(C_DOUBLE), PROTECTED, SAVE :: z0 = 0.d0 !< z origin (meters).
  REAL(C_DOUBLE), PROTECTED, SAVE :: vconst = 5000.d0 !< Constant velocity (m/s)
  REAL(C_DOUBLE), PROTECTED, SAVE :: vtop    = 5.d3   !< Velocity at top of layer.
  REAL(C_DOUBLE), PROTECTED, SAVE :: vbottom = 5.d3   !< Velocity at bottom of layer.
  !> Travel times to points in model (seconds).  This is an array of dimension
  !> [nz x ny x nx]. 
  REAL(C_DOUBLE), PROTECTED, ALLOCATABLE, SAVE :: ttimes(:)

  INTEGER(C_INT), PROTECTED, SAVE :: nrec !< Number of receivers.
  REAL(C_DOUBLE), PROTECTED, ALLOCATABLE, SAVE :: xrec(:) !< Receiver positions (m) in x.
  REAL(C_DOUBLE), PROTECTED, ALLOCATABLE, SAVE :: yrec(:) !< Receiver positions (m) in y.
  REAL(C_DOUBLE), PROTECTED, ALLOCATABLE, SAVE :: zrec(:) !< Receiver positions (m) in z. 
  REAL(C_DOUBLE), PROTECTED, ALLOCATABLE, SAVE :: trec(:) !< Travel time (s) at receiver.
  !-----------------------------------Private Variables----------------------------------!
  !> Workspace for vectorizing acosh calls
  REAL(C_DOUBLE), PRIVATE, ALLOCATABLE, SAVE :: work(:)
  REAL(C_DOUBLE), PRIVATE, ALLOCATABLE, SAVE :: wrec(:)
  ! Private variables
  INTEGER(C_INT), PRIVATE, SAVE :: ngrd = 0 
  !> Velocity gradient in principle directions.
  REAL(C_DOUBLE), PRIVATE, SAVE :: vGradInX = 0.d0
  REAL(C_DOUBLE), PRIVATE, SAVE :: vGradInY = 0.d0
  REAL(C_DOUBLE), PRIVATE, SAVE :: vGradInZ = 0.d0
  REAL(C_DOUBLE), PRIVATE, SAVE :: slow0 = 1.d0 !< Slowness (s/m) at source depth.
  REAL(C_DOUBLE), PRIVATE, SAVE :: vel0  = 1.d0 !< Velocity (m/s) at source depth.
  REAL(C_DOUBLE), PRIVATE, SAVE :: absG2 = 0.d0 !< Magnitude^2 of velocity gradient.
  REAL(C_DOUBLE), PRIVATE, SAVE :: absG  = 0.D0 !< Magnitude of velocity gradient.
  !> Flag indicating the module is initialized.
  LOGICAL, PRIVATE, SAVE :: linit = .FALSE.
  !-----------------------------Label the Subroutines/Functions--------------------------!
  PUBLIC :: fteik_analytic_initialize 
  PUBLIC :: fteik_analytic_free
  PUBLIC :: fteik_analytic_setReceivers64f
  PUBLIC :: fteik_analytic_setConstantVelocity
  PUBLIC :: fteik_analytic_setVelocityGradient 
  PUBLIC :: fteik_analytic_computeInGradientVelocityField
  PUBLIC :: fteik_analytic_computeInConstantVelocityField
  PUBLIC :: fteik_analytic_getTravelTimeField 
  PRIVATE :: fteik_analytic_setOrigin
  PRIVATE :: initializeGradientVars
  PRIVATE :: ttimeInConstantVelocity
  PRIVATE :: acoshArg
  CONTAINS
!----------------------------------------------------------------------------------------!
!                                     Begin the code                                     !
!----------------------------------------------------------------------------------------!
!>    @brief Initializes the 1D analytic travel time calculator module.  Note, the model
!>           is oriented so that +x is right (east), +y is away (north), and +z is
!>           down.
!> 
!>    @param[in] nxIn    Number of x grid points in model.  This must be positive.
!>    @param[in] nyIn    Number of y grid points in model.  This must be positive.
!>    @param[in] nzIn    Number of z grid points in model.  This must be positive.
!>    @param[in] dxIn    Grid spacing in x (meters).  This must be positive.
!>    @param[in] dyIn    Grid spacing in y (meters).  This must be positive.
!>    @param[in] dzIn    Grid spacing in z (meters).  This must be positive.
!>    @param[in] x0In    x origin (meters).
!>    @param[in] y0In    y origin (meters).
!>    @param[in] z0In    z origin (meters).
!>
!>    @param[out] ierr   0 indicates success.
!>
!>    @copyright Ben Baker distributed under the MIT license.
!>
      SUBROUTINE fteik_analytic_initialize(nxIn, nyIn, nzIn, &
                                           dxIn, dyIn, dzIn, &
                                           x0In, y0In, z0In, &
                                           ierr)             &
      BIND(C, NAME='fteik_analytic_initialize')
      USE ISO_C_BINDING
      IMPLICIT NONE
      INTEGER(C_INT), VALUE, INTENT(IN) :: nxIn, nyIn, nzIn
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: dxIn, dyIn, dzIn, x0In, y0In, z0In
      INTEGER(C_INT), INTENT(OUT) :: ierr
      ierr = 0
      IF (nxIn < 1 .OR. nyIn < 1 .OR. nzIn < 1) THEN
         WRITE(*,*) 'fteik_analytic_initialize: Invalid number of grid points', &
                    nxIn, nyIn, nzIn
         ierr = 1
         RETURN
      ENDIF
      IF (dxIn <= 0.d0 .OR. dyIn <= 0.d0 .OR. dzIn <= 0.d0) THEN
         WRITE(*,*) 'fteik_analytic_initialize: Grid spacing must be positive', &
                    dxIn, dyIn, dzIn
         ierr = 1
         RETURN
      ENDIF
      nrec = 0
      nx = nxIn
      ny = nyIn
      nz = nzIn
      ngrd = nx*ny*nz
      dx = dxIn
      dy = dyin
      dz = dzIn 
      CALL fteik_analytic_setOrigin(x0In, y0In, z0In, ierr)
      IF (ALLOCATED(ttimes)) DEALLOCATE(ttimes)
      IF (ALLOCATED(work))   DEALLOCATE(work)
      IF (ALLOCATED(xrec))   DEALLOCATE(xrec)
      IF (ALLOCATED(yrec))   DEALLOCATE(yrec)
      IF (ALLOCATED(zrec))   DEALLOCATE(zrec)
      IF (ALLOCATED(wrec))   DEALLOCATE(wrec)
      IF (ALLOCATED(trec))   DEALLOCATE(trec)
      ALLOCATE(ttimes(ngrd))
      ALLOCATE(work(ngrd))
      ttimes(:) = 0.d0
      linit = .TRUE.
      RETURN
      END SUBROUTINE
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Releases memory on the analytic travel time module. 
!>
!>    @copyright Ben Baker distributed under the MIT license.
!>
      SUBROUTINE fteik_analytic_free()  &
      BIND(C, NAME='fteik_analytic_free')
      USE ISO_C_BINDING
      IMPLICIT NONE
      IF (ALLOCATED(ttimes)) DEALLOCATE(ttimes)
      IF (ALLOCATED(work))   DEALLOCATE(work)
      IF (ALLOCATED(work))   DEALLOCATE(work)
      IF (ALLOCATED(xrec))   DEALLOCATE(xrec)
      IF (ALLOCATED(yrec))   DEALLOCATE(yrec)
      IF (ALLOCATED(zrec))   DEALLOCATE(zrec)
      IF (ALLOCATED(wrec))   DEALLOCATE(wrec)
      IF (ALLOCATED(trec))   DEALLOCATE(trec)
      nrec = 0
      nx = 0
      ny = 0
      nz = 0
      ngrd = 0
      dx = 0.d0
      dy = 0.d0
      dz = 0.d0
      x0 = 0.d0
      y0 = 0.d0
      z0 = 0.d0
      vtop = 5.d3
      vbottom = 5.d3
      vconst = 5.d3
      linit = .FALSE.
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Sets receivers at which to compute travel times.
!>
!>    @param[in] nrecIn   Number of receivers.
!>    @param[in] xrecIn   x positions of receivers.  This is an array of
!>                        dimension [nrecIn].
!>    @param[in] yrecIn   y positions of receivers.  This is an array of
!>                        dimension [nrecIn].
!>    @param[in] zrecIn   x positions of receivers.  This is an array of
!>                        dimension [nrecIn].
!>
!>    @param[out] ierr    0 indicates success.
!>
      SUBROUTINE fteik_analytic_setReceivers64f(nrecIn, xrecIn, yrecIn, zrecIn, ierr) &
      BIND(C, NAME='fteik_analytic_setReceivers64f')
      USE ISO_C_BINDING
      IMPLICIT NONE
      INTEGER(C_INT), VALUE, INTENT(IN) :: nrecIn
      REAL(C_DOUBLE), INTENT(IN) :: xrecIn(nrecIn), yrecIn(nrecIn), zrecIn(nrecIn)
      INTEGER(C_INT), INTENT(OUT) :: ierr
      REAL(C_DOUBLE) xmin, xmax, ymin, ymax, zmin, zmax
      ierr = 0
      IF (nrecIn < 1) THEN
         WRITE(*,*) 'fteik_analytic_setReceivers64f: No receivers locations to set'
         RETURN
      ENDIF
      IF (.NOT.linit) THEN
         WRITE(*,*) 'fteik_analytic_setReceivers64f: Model not initialized'
         ierr = 1
         RETURN
      ENDIF
      nrec = nrecIn
      xmin = x0
      xmax = x0 + REAL(nx - 1)*dx
      ymin = y0
      ymax = y0 + REAL(ny - 1)*dy
      zmin = z0
      zmax = z0 + REAL(nz - 1)*dz
      IF (ALLOCATED(xrec)) DEALLOCATE(xrec)
      IF (ALLOCATED(yrec)) DEALLOCATE(yrec)
      IF (ALLOCATED(zrec)) DEALLOCATE(zrec)
      IF (ALLOCATED(wrec)) DEALLOCATE(wrec)
      IF (ALLOCATED(trec)) DEALLOCATE(trec)
      ALLOCATE(xrec(nrec))
      ALLOCATE(yrec(nrec))
      ALLOCATE(zrec(nrec))
      ALLOCATE(wrec(nrec))
      ALLOCATE(trec(nrec))
      xrec(1:nrec) = xrecIn(1:nrec)
      yrec(1:nrec) = yrecIn(1:nrec)
      zrec(1:nrec) = zrecIn(1:nrec)
      trec(1:nrec) = 0.d0
      IF (MINVAL(xrec) < xmin .OR. MAXVAL(xrec) > xmax .OR. &
          MINVAL(yrec) < ymin .OR. MAXVAL(yrec) > ymax .OR. &
          MINVAL(zrec) < zmin .OR. MAXVAL(zrec) > zmax) THEN
         WRITE(*,*) 'fteik_analytic_setReceivers64f: Some receivers outside of model'
      ENDIF
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Sets the velocity in the constant velocity model.
!>
!>    @param[in] vconstIn   Constant velocity (m/s) to set.
!>
!>    @param[out] ierr      0 indicates success.
!>
      SUBROUTINE fteik_analytic_setConstantVelocity(vconstIn, ierr) &
      BIND(C, NAME='fteik_anlytic_setConstantVelocity')
      USE ISO_C_BINDING
      IMPLICIT NONE
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: vconstIn
      INTEGER(C_INT), INTENT(OUT) :: ierr
      ierr = 0
      IF (vconstIn <= 0.d0) THEN
         WRITE(*,*) 'fteik_analytic_setConstantVelocity: Velocity must be postiive', &
                    vconstIn
         ierr = 1
         RETURN
      ENDIF
      vconst = vconstIn
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Sets the model origin.  Here +x is positive right, +y is positive away,
!>           and +z is positive down.
!>
!>    @param[in] x0In   x model origin (meters).
!>    @param[in] y0In   y model origin (meters).
!>    @param[in] z0In   z model origin (meters).
!>
!>    @param[out] ierr  0 indicates success.
!>
      SUBROUTINE fteik_analytic_setOrigin(x0In, y0In, z0In, ierr)
      USE ISO_C_BINDING
      IMPLICIT NONE
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: x0In, y0In, z0In
      INTEGER(C_INT), INTENT(OUT) :: ierr
      ierr = 0
      x0 = x0In
      y0 = y0In
      z0 = z0In 
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Sets the velocity at the top and bottom of layer in the velocity gradient
!>           model.
!>
!>    @param[in] v0     Velocity at the top of the model (m/s). The top of the model
!>                      is closer to the surface.
!>    @param[in] v1     Velocity at the bottom of the model (m/s). The bottom of the model
!>                      is closer to the center of the earth.
!>
!>    @param[out] ierr  0 indicates success.
!>
      SUBROUTINE fteik_analytic_setVelocityGradient(v0, v1, ierr) &
      BIND(C, NAME='fteik_analytic_setVelocityGradient')
      USE ISO_C_BINDING
      IMPLICIT NONE
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: v0, v1
      INTEGER(C_INT), INTENT(OUT) :: ierr
      ierr = 0
      vtop = vconst
      vbottom = vconst
      IF (v0 <= 0.d0) THEN
         WRITE(*,*) 'fteik_analytic_setVelocityGradient: Error v0 must be positive'
         ierr = 1
         RETURN
      ENDIF
      IF (nz < 2) THEN
         WRITE(*,*) 'fteik_analytic_setVelocityGradient: At least 2 points required in z'
         ierr = 1
         RETURN
      ENDIF
      vtop    = v0
      vbottom = v1
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Computes travel times in constant gradient velocity field.  See Fomel's
!>           Fast sweeping method for the factored eikonal equation
!>           https://www.math.uci.edu/~zhao/homepage/research_files/FS_factored.pdf
!>           for the formula.
!>
!>    @param[in] job    If job is 1 then compute the travel time field. \n
!>                      Otherwise compute the travel times to the receivers.
!>    @param[in] xsrc   x source location (meters).
!>    @param[in] ysrc   y source location (meters).
!>    @param[in] zsrc   z source location (meters).
!>
!>    @param[out] ierr  0 indicates success.
!>
      SUBROUTINE fteik_analytic_computeInGradientVelocityField(job,              &
                                                               xsrc, ysrc, zsrc, &
                                                               ierr)             &
      BIND(C, NAME='fteik_analytic_computeInGradientVelocityField')
      USE ISO_C_BINDING
      IMPLICIT NONE
      INTEGER(C_INT), VALUE, INTENT(IN) :: job
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: xsrc, ysrc, zsrc
      INTEGER(C_INT), INTENT(OUT) :: ierr
      REAL(C_DOUBLE) x, y, z
      INTEGER(C_INT) i, igrd, j, k
      ierr = 0
      IF (.NOT.linit) THEN
         WRITE(*,*) 'fteik_analytic_computeInGradientVelocityField: not initialized'
         ierr = 1 
         RETURN
      ENDIF 
      IF (nz < 2) THEN
         WRITE(*,*) 'fteik_analytic_computeInGradientVelocityField: nz < 2'
         ierr = 1
         RETURN
      ENDIF
      CALL initializeGradientVars(zsrc)
      ! Compute argument of acosh
      IF (job == 1) THEN
!        !$OMP PARALLEL DO COLLAPSE(2) &
!        !$OMP PRIVATE(i, igrd, j, k, x, y, z) &
!        !$OMP SHARED(nx, ny, nz, work) &
!        !$OMP FIRSTPRIVATE(dx, dy, dz, xsrc, ysrc, zsrc, x0, y0, z0) &
!        !$OMP FIRSTPRIVATE(vel0, vGradInX, vGradInY, vGradInZ) &
!        !$OMP DEFAULT(NONE)
         DO k=1,nz
            DO j=1,ny
               !$OMP SIMD
               DO i=1,nx
                  igrd = (k - 1)*nx*ny + (j - 1)*nx + i 
                  x = x0 + REAL(i - 1)*dx
                  y = y0 + REAL(j - 1)*dy
                  z = z0 + REAL(k - 1)*dz
                  CALL acoshArg(x, y, z, xsrc, ysrc, zsrc,          &
                                vel0, vGradInX, vGradInY, vGradInZ, &
                                work(igrd))
               ENDDO
            ENDDO
         ENDDO
#ifdef MKL
         CALL vdAcosh(ngrd, work, ttimes)
#else
         DO i=1,ngrd
            ttimes(i) = ACOSH(work(i))
         ENDDO
#endif
         ttimes(:) = ttimes(:)/MAX(1.d-10, absG)
      ELSE
         !$OMP SIMD
         DO i=1,nrec
            CALL acoshArg(xrec(i), yrec(i), zrec(i),          &
                          xsrc, ysrc, zsrc,                   &
                          vel0, vGradInX, vGradInY, vGradInZ, &
                          wrec(i))
         ENDDO
#ifdef MKL
         CALL vdAcosh(nrec, wrec, trec)
#else
         DO i=1,ngrd
            trec(i) = ACOSH(wrec(i))
         ENDDO
#endif
      ENDIF
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Computes the travel times in the contant velocity field.  This simply
!>           computes travel time = distance/velocity.
!>
!>    @param[in] job    If job is 1 then compute the travel time field. \n
!>                      Otherwise compute the travel times to the receivers.
!>    @param[in] xsrc   x source offset from origin (meters).
!>    @param[in] ysrc   y source offset from origin (meters).
!>    @param[in] zsrc   z source offset from origin (meters).
!>
!>    @param[out] ierr  0 indicates success.
!>
      SUBROUTINE fteik_analytic_computeInConstantVelocityField(job,              &
                                                               xsrc, ysrc, zsrc, &
                                                               ierr)             &
      BIND(C, NAME='fteik_analytic_computeInConstantVelocityField')
      USE ISO_C_BINDING
      INTEGER(C_INT), VALUE, INTENT(IN) :: job
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: xsrc, ysrc, zsrc
      INTEGER(C_INT), INTENT(OUT) :: ierr
      REAL(C_DOUBLE) x, y, z
      INTEGER(C_INT) i, igrd, j, k
      ierr = 0
      IF (.NOT.linit) THEN
         WRITE(*,*) 'fteik_analytic_computeInConstantVelocityField: Not initialized'
         ierr = 1
         RETURN
      ENDIF
      IF (job == 1) THEN
!        !$OMP PARALLEL DO COLLAPSE(2) &
!        !$OMP PRIVATE(i, igrd, j, k, x, y, z) &
!        !$OMP SHARED(nx, ny, nz, ttimes) &
!        !$OMP FIRSTPRIVATE(dx, dy, dz, xsrc, ysrc, zsrc, x0, y0, z0, vconst) &
!        !$OMP DEFAULT(NONE)
         DO k=1,nz
            DO j=1,ny
               !$OMP SIMD
               DO i=1,nx
                  igrd = (k - 1)*nx*ny + (j - 1)*nx + i 
                  x = x0 + REAL(i - 1)*dx
                  y = y0 + REAL(j - 1)*dy
                  z = z0 + REAL(k - 1)*dz
                  ttimes(igrd) = ttimeInConstantVelocity(x, y, z,                &
                                                         xsrc, ysrc, zsrc, vconst)
               ENDDO
            ENDDO
         ENDDO 
      ELSE
         !$OMP SIMD
         DO i=1,nrec
            trec(i) = ttimeInConstantVelocity(xrec(i), yrec(i), zrec(i), &
                                              xsrc, ysrc, zsrc, vconst)
         ENDDO
      ENDIF
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Copies the analytic travel time.
!>
!>    @param[in] ngin    Number of input grid points.  This must equal [nz x nx x ny].
!>    @param[in] order   Desired ordering of output. \n
!>                       If order == FTEIK_NATURAL_ORDERING or FTEIK_ZXY_ORDERING then
!>                       ttimes will be [nz x nx ny] with first leading dimension nz
!>                       and second leading dimension nx. \n
!>                       If order == FTEIK_XYZ_ORDERING then ttimes will be [nx x ny x nz]
!>                       with first leading dimension nx and second leading
!>                       dimension ny. \n
!>                       If order == FTEIK_ZYX_ORDERING Then ttimes will be [nz x ny x nx]
!>                       with first leading dimension nz and second leading 
!>                       dimension ny. \n
!>
!>    @param[out] ttout  Travel time field (seconds) at the grid points.  This is 
!>                       a [nz x nx x ny] vector.  The ordering is defined by order.
!>    @param[out] ierr   0 indicates success.
!>
!>    @copyright Ben Baker distributed under the MIT license.
!>
      SUBROUTINE fteik_analytic_getTravelTimeField(ngin, order, ttout, ierr) &
      BIND(C, NAME='fteik_analytic_getTravelTimeField')
      USE ISO_C_BINDING
      IMPLICIT NONE
      INTEGER(C_INT), VALUE, INTENT(IN) :: ngin, order
      REAL(C_DOUBLE), INTENT(OUT) :: ttout(ngin)
      INTEGER(C_INT), INTENT(OUT) :: ierr
      INTEGER(C_INT) indx, ix, iy, iz, jndx
      ierr = 0
      IF (.NOT.linit) THEN
         WRITE(*,*) 'fteik_analytic_getTravelTimeField: ttimes not initialized'
         ierr = 1
         RETURN
      ENDIF
      IF (ngin < ngrd) THEN
         WRITE(*,*) 'fteik_analytic_getTravelTimeField: Insufficient space to store field'
         ierr = 1
         RETURN
      ENDIF
      IF (order == FTEIK_XYZ_ORDERING) THEN
         ttout(1:ngrd) = ttimes(1:ngrd)
      ELSEIF (order == FTEIK_ZYX_ORDERING) THEN
         DO ix=1,nx
            DO iy=1,ny
               !$OMP SIMD
               DO iz=1,nz
                  indx = (iz - 1)*nx*ny + (iy - 1)*nx + ix
                  jndx = (ix - 1)*nz*ny + (iy - 1)*nz + iz
                  ttout(jndx) = ttimes(indx)
               ENDDO
            ENDDO
         ENDDO
      ELSE
         IF (order /= FTEIK_NATURAL_ORDERING .AND. order /= FTEIK_ZXY_ORDERING) THEN
            WRITE(*,*) 'fteik_analytic_getTravelTimeField: Defaulting to natural order'
         ENDIF 
         DO iy=1,ny
            DO ix=1,nx
               !$OMP SIMD
               DO iz=1,nz
                  indx = (iz - 1)*nx*ny + (iy - 1)*nx + ix 
                  jndx = (iy - 1)*nz*nx + (ix - 1)*nz + iz
                  ttout(jndx) = ttimes(indx)
               ENDDO
            ENDDO
         ENDDO 
      ENDIF
      IF (ngin > ngrd) ttout(ngrd+1:ngin) = 0.d0
      RETURN
      END
!                                                                                        !
!========================================================================================!
!                                                                                        !
!>    @brief Copies the travel time computed at the receivers from the module.
!>
!>    @param[in] nrecIn    Number of receivers in trecOut.  This should be at least nrec.
!>
!>    @param[out] trecOut  Travel times (seconds) at receivers.  This is an array of
!>                         dimension [nrecIn] where the first [nrec] points contains
!>                         the travel times at the receivers.
!>    @aram[out] ierr      0 indicates success.
!>
      SUBROUTINE ttimes1d_getTravelTimesAtReceivers(nrecIn, trecOut, ierr) &
      BIND(C, NAME='ttimes1d_getTravelTimesAtReceivers')
      USE ISO_C_BINDING
      IMPLICIT NONE
      INTEGER(C_INT), VALUE, INTENT(IN) :: nrecIn
      REAL(C_DOUBLE), INTENT(OUT) :: trecOut(nrecIn)
      INTEGER(C_INT), INTENT(OUT) :: ierr
      ierr = 0
      IF (.NOT.linit) THEN
         WRITE(*,*) 'ttimes1d_getTravelTimesAtReceivers: ttimes not initialized'
         ierr = 1
         RETURN
      ENDIF
      IF (nrecIn < nrec) THEN
         WRITE(*,*) 'ttimes1d_getTravelTimesAtReceivers: Insufficient space to store trec'
         ierr = 1
         RETURN
      ENDIF
      trecOut(1:nrec) = trec(1:nrec)
      IF (nrecIn > nrec) trecOut(nrec+1:nrecIn) = 0.d0
      RETURN
      END
!========================================================================================!
!                                   Private Functions                                    !
!========================================================================================!
      REAL(C_DOUBLE) FUNCTION ttimeInConstantVelocity(x, y, z, xsrc, ysrc, zsrc, vel)
      !$OMP DECLARE SIMD(ttimeInConstantVelocity) UNIFORM(xsrc, ysrc, zsrc, vel)
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: x, y, z, xsrc, ysrc, zsrc, vel
      REAL(C_DOUBLE) dist
      dist = SQRT( (x - xsrc)**2 + (y - ysrc)**2 + (z - zsrc)**2 )
      ttimeInConstantVelocity = dist/vel
      RETURN
      END

      SUBROUTINE acoshArg(x, y, z, xsrc, ysrc, zsrc,          &
                          vel0, vGradInX, vGradInY, vGradInZ, &
                          arg)
      !$OMP DECLARE SIMD(acoshArg) &
      !$OMP UNIFORM(xsrc, ysrc, zsrc, vel0, vGradInX, vGradInY, vGradInZ) 
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: x, y, z, xsrc, ysrc, zsrc
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: vel0, vGradInX, vGradInY, vGradInZ
      REAL(C_DOUBLE), INTENT(OUT) :: arg
      REAL(C_DOUBLE) dist2, dx, dy, dz, vel
      dx = x - xsrc
      dy = y - ysrc
      dz = z - zsrc
      dist2 = dx*dx + dy*dy + dz*dz
      !dist2 = (x - xsrc)**2 + (y - ysrc)**2 + (z - zsrc)**2
      vel = vel0 + vGradInX*dx + vGradInY*dy + vGradInZ*dz
      !vel = vel0 + vGradInX*(x - xsrc) + vGradInY*(y - ysrc) + vGradInZ*(z - zsrc)
      arg = 1.d0 + 0.5d0/vel*slow0*absG2*dist2
      !acoshArg = 1.d0 + 0.5d0/vel*slow0*absG2*dist2 
      RETURN
      END

      SUBROUTINE initializeGradientVars(zsrc)
      USE ISO_C_BINDING
      IMPLICIT NONE
      REAL(C_DOUBLE), VALUE, INTENT(IN) :: zsrc
      REAL(C_DOUBLE) vel1, ztop, zbot
      ztop = z0
      zbot = z0 + REAL(nz - 1)*dz
      vel0 = vtop + (vbottom - vtop)/(zbot - ztop)*zsrc ! Velocity at source depth
      vel1 = vbottom    ! This doesn't change
      slow0 = 1.d0/vel0 ! Slowness at soruce depth 
      vGradInX = 0.d0
      vGradInY = 0.d0
      vGradInZ = (vel1 - vel0)/(zbot - zsrc) ! Should match the initial gradient
      absG2 = vGradInX**2 + vGradInY**2 + vGradInZ**2
      absG  = SQRT(absG2)
      RETURN
      END
END MODULE