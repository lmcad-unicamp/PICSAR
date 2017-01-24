! ______________________________________________________________________________
!
! *** Copyright Notice ***
!
! “Particle In Cell Scalable Application Resource (PICSAR) v2”, Copyright (c)
! 2016, The Regents of the University of California, through Lawrence Berkeley
! National Laboratory (subject to receipt of any required approvals from the
! U.S. Dept. of Energy). All rights reserved.
!
! If you have questions about your rights to use or distribute this software,
! please contact Berkeley Lab's Innovation & Partnerships Office at IPO@lbl.gov.
!
! NOTICE.
! This Software was developed under funding from the U.S. Department of Energy
! and the U.S. Government consequently retains certain rights. As such, the U.S.
! Government has been granted for itself and others acting on its behalf a
! paid-up, nonexclusive, irrevocable, worldwide license in the Software to
! reproduce, distribute copies to the public, prepare derivative works, and
! perform publicly and display publicly, and to permit other to do so.
!
! FIELD_GATHERING_MANAGER.F90
!
! This file contains subroutines to manage the field gathering in 3D.
!
! Developers:
! - Henri vincenti
! - Mathieu Lobet
!
! options:
! - DEV: activates developer's secret subroutines
! - DEBUG: activates DEBUG prints and outputs
!
! List of subroutines:
!
! - field_gathering
! - field_gathering_sub
! - geteb3d_energy_conserving
!
! ______________________________________________________________________________


! ______________________________________________________________________________
!> @brief
!> Field gathering main subroutine in 3D called in the main loop when not coupled
!> with the particle pusher.
SUBROUTINE field_gathering
! ______________________________________________________________________________
  USE fields
  USE shared_data
  USE params
  USE time_stat
  IMPLICIT NONE

#if defined(DEBUG)
  WRITE(0,*) "Field gathering: start"
#endif

  CALL field_gathering_sub(ex,ey,ez,bx,by,bz,nx,ny,nz,nxguards,nyguards, &
   nzguards,nxjguards,nyjguards,nzjguards,nox,noy,noz,dx,dy,dz,dt,l_lower_order_in_v)


#if defined(DEBUG)
  WRITE(0,*) "Field gathering: stop"
#endif

END SUBROUTINE field_gathering


! ______________________________________________________________________________
!> @brief
!> This subroutine performs the field gathering in 3D only
SUBROUTINE field_gathering_sub(exg,eyg,ezg,bxg,byg,bzg,nxx,nyy,nzz, &
      nxguard,nyguard,nzguard,nxjguard,nyjguard,nzjguard,noxx,noyy,nozz,&
      dxx,dyy,dzz,dtt,l_lower_order_in_v_in)
! ______________________________________________________________________________
  USE particles
  USE constants
  USE tiling
  USE time_stat
  ! Vtune/SDE profiling
#if defined(VTUNE) && VTUNE==3
  USE ITT_FORTRAN
#endif
#if defined(SDE) && SDE==3
  USE SDE_FORTRAN
#endif
  IMPLICIT NONE

  ! ___ Parameter declaration ________________________________________
  INTEGER(idp), INTENT(IN) :: nxx,nyy,nzz,nxguard,nyguard,nzguard,nxjguard,nyjguard,nzjguard
  INTEGER(idp), INTENT(IN) :: noxx,noyy,nozz
  LOGICAL(lp)              :: l_lower_order_in_v_in
  REAL(num), INTENT(IN)    :: exg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN)    :: eyg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN)    :: ezg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN)    :: bxg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN)    :: byg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN)    :: bzg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN)    :: dxx,dyy,dzz, dtt
  INTEGER(idp)             :: ispecies, ix, iy, iz, count
  INTEGER(idp)             :: jmin, jmax, kmin, kmax, lmin, lmax
  TYPE(particle_species), POINTER :: curr
  TYPE(grid_tile), POINTER        :: currg
  TYPE(particle_tile), POINTER    :: curr_tile
  REAL(num)                :: tdeb, tend
  INTEGER(idp)             :: nxc, nyc, nzc, ipmin,ipmax, ip
  INTEGER(idp)             :: nxjg,nyjg,nzjg
  LOGICAL(lp)                   :: isgathered=.FALSE._lp

  IF (nspecies .EQ. 0_idp) RETURN

  IF (it.ge.timestat_itstart) THEN
    tdeb=MPI_WTIME()
  ENDIF

#if VTUNE==3
  CALL start_vtune_collection()
#endif
#if SDE==3
  CALL start_sde_collection()
#endif

  !$OMP PARALLEL DO COLLAPSE(3) SCHEDULE(runtime) DEFAULT(NONE) &
  !$OMP SHARED(ntilex,ntiley,ntilez,nspecies,species_parray,aofgrid_tiles, &
  !$OMP nxjguard,nyjguard,nzjguard,nxguard,nyguard,nzguard,exg,eyg,ezg,bxg,&
  !$OMP byg,bzg,dxx,dyy,dzz,dtt,noxx,noyy,nozz,c_dim,l_lower_order_in_v_in,fieldgathe, &
  !$OMP LVEC_fieldgathe) &
  !$OMP PRIVATE(ix,iy,iz,ispecies,curr,curr_tile, currg, count,jmin,jmax,kmin,kmax,lmin, &
  !$OMP lmax,nxc,nyc,nzc, ipmin,ipmax,ip,nxjg,nyjg,nzjg, isgathered)
  DO iz=1, ntilez ! LOOP ON TILES
    DO iy=1, ntiley
        DO ix=1, ntilex
          curr=>species_parray(1)
          curr_tile=>curr%array_of_tiles(ix,iy,iz)
          nxjg=curr_tile%nxg_tile
          nyjg=curr_tile%nyg_tile
          nzjg=curr_tile%nzg_tile
          jmin=curr_tile%nx_tile_min-nxjg
          jmax=curr_tile%nx_tile_max+nxjg
          kmin=curr_tile%ny_tile_min-nyjg
          kmax=curr_tile%ny_tile_max+nyjg
          lmin=curr_tile%nz_tile_min-nzjg
          lmax=curr_tile%nz_tile_max+nzjg
          nxc=curr_tile%nx_cells_tile
          nyc=curr_tile%ny_cells_tile
          nzc=curr_tile%nz_cells_tile
          isgathered=.FALSE._lp

          DO ispecies=1, nspecies ! LOOP ON SPECIES
            curr=>species_parray(ispecies)
            curr_tile=>curr%array_of_tiles(ix,iy,iz)
            count=curr_tile%np_tile(1)
            IF (count .GT. 0) isgathered=.TRUE.
          END DO
          IF (isgathered) THEN
            currg=>aofgrid_tiles(ix,iy,iz)
            currg%extile=exg(jmin:jmax,kmin:kmax,lmin:lmax)
            currg%eytile=eyg(jmin:jmax,kmin:kmax,lmin:lmax)
            currg%eztile=ezg(jmin:jmax,kmin:kmax,lmin:lmax)
            currg%bxtile=bxg(jmin:jmax,kmin:kmax,lmin:lmax)
            currg%bytile=byg(jmin:jmax,kmin:kmax,lmin:lmax)
            currg%bztile=bzg(jmin:jmax,kmin:kmax,lmin:lmax)
            DO ispecies=1, nspecies ! LOOP ON SPECIES
              ! - Get current tile properties
              ! - Init current tile variables

              curr=>species_parray(ispecies)
              curr_tile=>curr%array_of_tiles(ix,iy,iz)
              count=curr_tile%np_tile(1)
              IF (count .EQ. 0) CYCLE
              curr_tile%part_ex(1:count) = 0.0_num
              curr_tile%part_ey(1:count) = 0.0_num
              curr_tile%part_ez(1:count) = 0.0_num
              curr_tile%part_bx(1:count)=0.0_num
              curr_tile%part_by(1:count)=0.0_num
              curr_tile%part_bz(1:count)=0.0_num
              !!! ---- Loop by blocks over particles in a tile (blocking)
              !!! --- Gather electric field on particles

              !!! --- Gather electric and magnetic fields on particles
              CALL geteb3d_energy_conserving(count,curr_tile%part_x,curr_tile%part_y,            &
                          curr_tile%part_z, curr_tile%part_ex,                                   &
                          curr_tile%part_ey,curr_tile%part_ez,                                    &
                          curr_tile%part_bx, curr_tile%part_by,curr_tile%part_bz,                &
                          curr_tile%x_grid_tile_min,curr_tile%y_grid_tile_min,                   &
                          curr_tile%z_grid_tile_min, dxx,dyy,dzz,curr_tile%nx_cells_tile,  &
                          curr_tile%ny_cells_tile,curr_tile%nz_cells_tile,nxjg,nyjg,             &
                          nzjg,noxx,noyy,nozz,currg%extile,currg%eytile,                          &
                          currg%eztile,                                                           &
                          currg%bxtile,currg%bytile,currg%bztile                                  &
                          ,.FALSE._lp,l_lower_order_in_v_in,LVEC_fieldgathe, &
                          fieldgathe)

                END DO! END LOOP ON SPECIES
            ENDIF
        END DO
    END DO
  END DO! END LOOP ON TILES
  !$OMP END PARALLEL DO

#if VTUNE==3
  CALL stop_vtune_collection()
#endif
#if SDE==3
  CALL stop_sde_collection()
#endif

  IF (it.ge.timestat_itstart) THEN
    tend=MPI_WTIME()
    localtimes(14) = localtimes(14) + (tend-tdeb)
  ENDIF

END SUBROUTINE field_gathering_sub


! ______________________________________________________________________________
!> @brief
!> General subroutines for the 3D field gathering
!
!> @details
!> This subroutine controls the different algorithms for the field gathering
!> Choice of an algorithm is done using the argument field_gathe_algo.
!> This subroutine is called in the subroutine field_gathering_sub().
!
!> @author
!> Henri Vincenti
!> Mathieu Lobet
!
!> @date
!> 2015-2016
!
!> @param[in] np number of particles
!> @param[in] xp,yp,zp particle positions
!> @param[out] ex,ey,ez particle electric field
!> @param[out] bx,by,bz particle magnetic field
!> @param[in] xmin,ymin,zmin tile origin
!> @param[in] dx,dy,dz space discretization
!> @param[in] nx,ny,nz number of cells in each direction
!> @param[in] nxguard,nyguard,nzguard number of guard cells in each direction
!> @param[in] nox,noy,noz shape factor order
!> @param[in] exg,eyg,ezg electric field grids
!> @param[in] bxg,byg,bzg magnetic field grids
!> @param[in] ll4symtry
!> @param[in] l_lower_order_in_v
!> @param[in] field_gathe_algo gathering algorithm
!> @param[in] lvect vector length
!
SUBROUTINE geteb3d_energy_conserving(np,xp,yp,zp,ex,ey,ez,bx,by,bz, &
                                     xmin,ymin,zmin,          &
                                     dx,dy,dz,nx,ny,nz,       &
                                     nxguard,nyguard,nzguard, &
                                     nox,noy,noz,             &
                                     exg,eyg,ezg,bxg,byg,bzg, &
                                     ll4symtry,               &
                                     l_lower_order_in_v,      &
                                     lvect,                   &
                                     field_gathe_algo)
! ______________________________________________________________________________

  USE constants
  USE particles
  USE params
  implicit none

  integer(idp)                  :: field_gathe_algo
  integer(idp)                  :: np,nx,ny,nz,nox,noy,noz,nxguard,nyguard,nzguard
  LOGICAL(lp) , intent(in)      :: ll4symtry,l_lower_order_in_v
  real(num), dimension(np)      :: xp,yp,zp,ex,ey,ez,bx,by,bz
  real(num)                     :: xmin,ymin,zmin,dx,dy,dz
  integer(idp)                  :: lvect
  real(num), dimension(-nxguard:nx+nxguard,-nyguard:ny+nyguard,-nzguard:nz+nzguard) :: exg,eyg,ezg
  real(num), dimension(-nxguard:nx+nxguard,-nyguard:ny+nyguard,-nzguard:nz+nzguard) :: bxg,byg,bzg

  IF (np .EQ. 0_idp) RETURN

  SELECT CASE(field_gathe_algo)

! ______________________________________________________________________________
! Developer's functions (experimental or under development)
#if defined(DEV)

    ! ______________________________________
    ! Vectorized non efficient field gathering subroutines
    CASE(6)

      IF ((nox.eq.1).and.(noy.eq.1).and.(noz.eq.1)) THEN
        !!! --- Gather electric fields on particles
        CALL geteb3d_energy_conserving_vecV1_1_1_1(np,xp,yp,zp,ex,ey,ez,bx,by,bz,xmin,ymin,zmin,  &
                                      dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                      exg,eyg,ezg,bxg,byg,bzg,LVEC_fieldgathe,l_lower_order_in_v)

      ELSE IF ((nox.eq.2).and.(noy.eq.2).and.(noz.eq.2)) THEN
        !!! --- Gather electric fields on particles
        CALL geteb3d_energy_conserving_vecV1_2_2_2(np,xp,yp,zp,ex,ey,ez,bx,by,bz,xmin,ymin,zmin,  &
                                      dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                      exg,eyg,ezg,bxg,byg,bzg,LVEC_fieldgathe,l_lower_order_in_v)

      ELSE IF ((nox.eq.3).and.(noy.eq.3).and.(noz.eq.3)) THEN
        !!! --- Gather electric fields on particles
        CALL geteb3d_energy_conserving_vec_3_3_3(np,xp,yp,zp,ex,ey,ez,bx,by,bz,xmin,ymin,zmin,  &
                                      dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                      exg,eyg,ezg,bxg,byg,bzg,LVEC_fieldgathe,l_lower_order_in_v)
      ELSE
        !!! --- Gather electric field on particles
        CALL pxr_gete3d_n_energy_conserving(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,exg,eyg,ezg,ll4symtry,l_lower_order_in_v)
        !!! --- Gather magnetic fields on particles
        CALL pxr_getb3d_n_energy_conserving(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,bxg,byg,bzg,ll4symtry,l_lower_order_in_v)
      ENDIF

    ! ______________________________________
    ! Vectorized field gathering subroutines, separated E and B functions
    CASE(5)

      IF ((nox.eq.3).and.(noy.eq.3).and.(noz.eq.3)) THEN
        !!! --- Gather electric fields on particles
        CALL gete3d_energy_conserving_vec2_3_3_3(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,       &
                                      dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                      exg,eyg,ezg,LVEC_fieldgathe,l_lower_order_in_v)
        !!! --- Gather magnetic fields on particles
        CALL getb3d_energy_conserving_vec2_3_3_3(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,       &
                                      dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                      bxg,byg,bzg,LVEC_fieldgathe,l_lower_order_in_v)
      ELSE
        !!! --- Gather electric field on particles
        CALL pxr_gete3d_n_energy_conserving(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,exg,eyg,ezg,ll4symtry,l_lower_order_in_v)
        !!! --- Gather magnetic fields on particles
        CALL pxr_getb3d_n_energy_conserving(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,bxg,byg,bzg,ll4symtry,l_lower_order_in_v)
      ENDIF

    ! ______________________________________
    ! Vectorized field gathering subroutine by block splited into smaller loops
    CASE(4)

      IF ((nox.eq.3).and.(noy.eq.3).and.(noz.eq.3)) THEN
        !!! --- Gather electric and magnetic fields on particles
        CALL geteb3d_energy_conserving_blockvec2_3_3_3(np,xp,yp,zp,ex,ey,ez,bx,by,bz, &
                      xmin,ymin,zmin,dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                      exg,eyg,ezg,bxg,byg,bzg,LVEC_fieldgathe,l_lower_order_in_v)
      ELSE
        !!! --- Gather electric field on particles
        CALL pxr_gete3d_n_energy_conserving(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,exg,eyg,ezg,ll4symtry,l_lower_order_in_v)
        !!! --- Gather magnetic fields on particles
        CALL pxr_getb3d_n_energy_conserving(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,bxg,byg,bzg,ll4symtry,l_lower_order_in_v)
      ENDIF

    ! ______________________________________
    ! Linearized field gathering subroutines
    CASE(3)

      IF ((nox.eq.3).and.(noy.eq.3).and.(noz.eq.3)) THEN
        !!! --- Gather electric field on particles
        CALL gete3d_energy_conserving_linear_3_3_3(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,   &
                                          dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                          exg,eyg,ezg,l_lower_order_in_v)
        !!! --- Gather magnetic fields on particles
        CALL getb3d_energy_conserving_linear_3_3_3(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,   &
                                          dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                          bxg,byg,bzg,l_lower_order_in_v)
      ELSE
        !!! --- Gather electric field on particles
        CALL pxr_gete3d_n_energy_conserving(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,exg,eyg,ezg,ll4symtry,l_lower_order_in_v)
        !!! --- Gather magnetic fields on particles
        CALL pxr_getb3d_n_energy_conserving(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,&
                                     dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                     nox,noy,noz,bxg,byg,bzg,ll4symtry,l_lower_order_in_v)
      ENDIF

#endif
! ______________________________________________________________________________

  ! ______________________________________________
  ! Arbitrary order, non-optimized subroutines
  CASE(2)

    !!! --- Gather electric field on particles
    CALL pxr_gete3d_n_energy_conserving(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,&
                                 dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                 nox,noy,noz,exg,eyg,ezg,ll4symtry,l_lower_order_in_v)
    !!! --- Gather magnetic fields on particles
    CALL pxr_getb3d_n_energy_conserving(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,&
                                 dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                 nox,noy,noz,bxg,byg,bzg,ll4symtry,l_lower_order_in_v)

  ! ______________________________________________
  ! Non-optimized scalar subroutines

  CASE(1)

    IF ((nox.eq.1).and.(noy.eq.1).and.(noz.eq.1)) THEN
      !!! --- Gather electric field on particles
      CALL gete3d_energy_conserving_scalar_1_1_1(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,   &
                                        dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                        exg,eyg,ezg,l_lower_order_in_v)
      !!! --- Gather magnetic fields on particles
      CALL getb3d_energy_conserving_scalar_1_1_1(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,   &
                                        dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                        bxg,byg,bzg,l_lower_order_in_v)

    ELSE IF ((nox.eq.2).and.(noy.eq.2).and.(noz.eq.2)) THEN
      !!! --- Gather electric field on particles
      CALL gete3d_energy_conserving_scalar_2_2_2(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,   &
                                        dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                        exg,eyg,ezg,l_lower_order_in_v)
      !!! --- Gather magnetic fields on particles
      CALL getb3d_energy_conserving_scalar_2_2_2(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,   &
                                        dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                        bxg,byg,bzg,l_lower_order_in_v)
    ELSE IF ((nox.eq.3).and.(noy.eq.3).and.(noz.eq.3)) THEN
      !!! --- Gather electric field on particles
      CALL gete3d_energy_conserving_scalar_3_3_3(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,   &
                                        dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                        exg,eyg,ezg,l_lower_order_in_v)
      !!! --- Gather magnetic fields on particles
      CALL getb3d_energy_conserving_scalar_3_3_3(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,   &
                                        dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                        bxg,byg,bzg,l_lower_order_in_v)
    ELSE
    !!! --- Gather electric field on particles
    CALL pxr_gete3d_n_energy_conserving(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,&
                                 dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                 nox,noy,noz,exg,eyg,ezg,ll4symtry,l_lower_order_in_v)
    !!! --- Gather magnetic fields on particles
    CALL pxr_getb3d_n_energy_conserving(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,&
                                 dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                 nox,noy,noz,bxg,byg,bzg,ll4symtry,l_lower_order_in_v)
    ENDIF


  ! ________________________________________
  ! Optimized subroutines, E and B in the same vectorized loop, default
  CASE DEFAULT

    IF ((nox.eq.1).and.(noy.eq.1).and.(noz.eq.1)) THEN

      CALL geteb3d_energy_conserving_vecV3_1_1_1(np,xp,yp,zp,ex,ey,ez,bx,by,bz, &
                      xmin,ymin,zmin,dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                      exg,eyg,ezg,bxg,byg,bzg,lvect,l_lower_order_in_v)

    ELSE IF ((nox.eq.2).and.(noy.eq.2).and.(noz.eq.2)) THEN

      CALL geteb3d_energy_conserving_vecV3_2_2_2(np,xp,yp,zp,ex,ey,ez,bx,by,bz, &
                      xmin,ymin,zmin,dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                      exg,eyg,ezg,bxg,byg,bzg,lvect,l_lower_order_in_v)

    ELSE IF ((nox.eq.3).and.(noy.eq.3).and.(noz.eq.3)) THEN

      CALL geteb3d_energy_conserving_vec2_3_3_3(np,xp,yp,zp,ex,ey,ez,bx,by,bz, &
                      xmin,ymin,zmin,dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                      exg,eyg,ezg,bxg,byg,bzg,lvect,l_lower_order_in_v)

    ! Arbitrary order
    ELSE
      !!! --- Gather electric field on particles
      CALL pxr_gete3d_n_energy_conserving(np,xp,yp,zp,ex,ey,ez,xmin,ymin,zmin,&
                                   dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                   nox,noy,noz,exg,eyg,ezg,ll4symtry,l_lower_order_in_v)
      !!! --- Gather magnetic fields on particles
      CALL pxr_getb3d_n_energy_conserving(np,xp,yp,zp,bx,by,bz,xmin,ymin,zmin,&
                                   dx,dy,dz,nx,ny,nz,nxguard,nyguard,nzguard, &
                                   nox,noy,noz,bxg,byg,bzg,ll4symtry,l_lower_order_in_v)
    ENDIF
  END SELECT

END SUBROUTINE