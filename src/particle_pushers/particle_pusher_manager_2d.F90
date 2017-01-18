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
! PARTICLE_PUSHER_MANAGER_2D.F90
!
! Subroutines for managing the particle pushers in 2d.
! ______________________________________________________________________________


! ________________________________________________________________________________________
!> @brief
!> This subroutine is the 2D version of the particle pusher + field gathering
!
!> @author
!> Henri Vincenti
!> Mathieu Lobet
!
!> @date
!> Creation 2016
!
!> @param[in] exg,eyg,ezg electric field grids
!> @param[in] bxg,byg,bzg magnetic field grids
!> @param[in] nxx,nyy,nzz number of cells in each direction for the grids, nyy should be equal to 1.
!> @param[in] nxguard,nyguard,nzguard number of guard cells in each direction for the grids
!> @param[in] nxjguard,nyjguard,nzjguard number of guard cells for the current grids
!> @param[in] noxx,noyy,nozz interpolation orders
!> @param[in] dxx,dyy,dzz space steps
!> @param[in] dtt time step
!
SUBROUTINE field_gathering_plus_particle_pusher_sub_2d(exg,eyg,ezg, &
                                                       bxg,byg,bzg, &
                                                       nxx,nyy,nzz, &
                                                       nxguard,nyguard,nzguard, &
                                                       nxjguard,nyjguard,nzjguard, &
                                                       noxx,noyy,nozz,dxx,dyy,dzz,dtt)
! ________________________________________________________________________________________
  USE particles
  USE constants
  USE tiling
  USE time_stat
  
! Vtune/SDE profiling
#if defined(PROFILING) && PROFILING==3  
  USE ITT_SDE_FORTRAN                   
#endif

  IMPLICIT NONE
  INTEGER(idp), INTENT(IN) :: nxx,nyy,nzz,nxguard,nyguard,nzguard,nxjguard,nyjguard,nzjguard
  INTEGER(idp), INTENT(IN) :: noxx,noyy,nozz
  REAL(num), INTENT(IN) :: exg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN) :: eyg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN) :: ezg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN) :: bxg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN) :: byg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN) :: bzg(-nxguard:nxx+nxguard,-nyguard:nyy+nyguard,-nzguard:nzz+nzguard)
  REAL(num), INTENT(IN) :: dxx,dyy,dzz, dtt
  INTEGER(idp) :: ispecies, ix, iy, iz, count
  INTEGER(idp) :: jmin, jmax, kmin, kmax, lmin, lmax
  TYPE(particle_species), POINTER :: curr
  TYPE(grid_tile), POINTER :: currg
  TYPE(particle_tile), POINTER :: curr_tile
  REAL(num) :: tdeb, tend
  INTEGER(idp) :: nxc, nyc, nzc, ipmin,ipmax, ip
  INTEGER(idp) :: nxjg,nyjg,nzjg
  LOGICAL(lp)  :: isgathered=.FALSE.

  tdeb=MPI_WTIME()

#if PROFILING==3               
  CALL start_collection()      
#endif                         


  !$OMP PARALLEL DO COLLAPSE(2) SCHEDULE(runtime) DEFAULT(NONE) &
  !$OMP SHARED(ntilex,ntiley,ntilez,nspecies,species_parray,aofgrid_tiles, &
  !$OMP nxjguard,nyjguard,nzjguard,nxguard,nyguard,nzguard,exg,eyg,ezg,bxg,&
  !$OMP byg,bzg,dxx,dyy,dzz,dtt,noxx,noyy,nozz,c_dim,fieldgathe,LVEC_fieldgathe) &
  !$OMP PRIVATE(ix,iy,iz,ispecies,curr,curr_tile, currg, count,jmin,jmax,kmin,kmax,lmin, &
  !$OMP lmax,nxc,nyc,nzc, ipmin,ipmax,ip,nxjg,nyjg,nzjg, isgathered)
  DO iz=1, ntilez ! LOOP ON TILES
    DO ix=1, ntilex
      curr=>species_parray(1)
      curr_tile=>curr%array_of_tiles(ix,1,iz)
      nxjg=curr_tile%nxg_tile

      nzjg=curr_tile%nzg_tile
      jmin=curr_tile%nx_tile_min-nxjg
      jmax=curr_tile%nx_tile_max+nxjg
      lmin=curr_tile%nz_tile_min-nzjg
      lmax=curr_tile%nz_tile_max+nzjg
      nxc=curr_tile%nx_cells_tile
      nzc=curr_tile%nz_cells_tile
      isgathered=.FALSE.
      DO ispecies=1, nspecies ! LOOP ON SPECIES
        curr=>species_parray(ispecies)
        curr_tile=>curr%array_of_tiles(ix,1,iz)
        count=curr_tile%np_tile(1)
        IF (count .GT. 0) isgathered=.TRUE.
      END DO
      IF (isgathered) THEN
        currg=>aofgrid_tiles(ix,1,iz)
        currg%extile=exg(jmin:jmax,1:1,lmin:lmax)
        currg%eytile=eyg(jmin:jmax,1:1,lmin:lmax)
        currg%eztile=ezg(jmin:jmax,1:1,lmin:lmax)
        currg%bxtile=bxg(jmin:jmax,1:1,lmin:lmax)
        currg%bytile=byg(jmin:jmax,1:1,lmin:lmax)
        currg%bztile=bzg(jmin:jmax,1:1,lmin:lmax)
        DO ispecies=1, nspecies ! LOOP ON SPECIES
          ! - Get current tile properties
          ! - Init current tile variables
          curr=>species_parray(ispecies)
          curr_tile=>curr%array_of_tiles(ix,1,iz)
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
          CALL geteb2dxz_energy_conserving(count,curr_tile%part_x,curr_tile%part_y,           &
                      curr_tile%part_z, curr_tile%part_ex,                              &
                      curr_tile%part_ey,curr_tile%part_ez,                         &
                      curr_tile%part_bx, curr_tile%part_by,curr_tile%part_bz,       &
                      curr_tile%x_grid_tile_min,curr_tile%y_grid_tile_min,              &
                      curr_tile%z_grid_tile_min, dxx,dyy,dzz,curr_tile%nx_cells_tile,   &
                      curr_tile%ny_cells_tile,curr_tile%nz_cells_tile,nxjg,nyjg,        &
                      nzjg,noxx,noyy,nozz,currg%extile,currg%eytile,           &
                      currg%eztile,                                                &
                      currg%bxtile,currg%bytile,currg%bztile                       &
                      ,.FALSE.,.TRUE., &
                      LVEC_fieldgathe, &
                      fieldgathe)

          !! --- Push velocity with E half step
          CALL pxr_epush_v(count,curr_tile%part_ux, curr_tile%part_uy,                    &
          curr_tile%part_uz, curr_tile%part_ex, curr_tile%part_ey,               &
          curr_tile%part_ez, curr%charge,curr%mass,dtt*0.5_num)
          !! --- Set gamma of particles 
          CALL pxr_set_gamma(count,curr_tile%part_ux, curr_tile%part_uy,                  &
          curr_tile%part_uz, curr_tile%part_gaminv)
          !! --- Push velocity with B half step
          CALL pxr_bpush_v(count,curr_tile%part_ux, curr_tile%part_uy,                    &
          curr_tile%part_uz,curr_tile%part_gaminv, curr_tile%part_bx, curr_tile%part_by,  &
          curr_tile%part_bz, curr%charge,curr%mass,dtt)
          !!! --- Push velocity with E half step
          CALL pxr_epush_v(count,curr_tile%part_ux, curr_tile%part_uy,                       &
          curr_tile%part_uz, curr_tile%part_ex, curr_tile%part_ey,                        &
          curr_tile%part_ez, curr%charge,curr%mass,dtt*0.5_num)
          !! --- Set gamma of particles 
          CALL pxr_set_gamma(count,curr_tile%part_ux, curr_tile%part_uy,                  &
          curr_tile%part_uz, curr_tile%part_gaminv)
          !!!! --- push particle species positions a time step
          CALL pxr_push2dxz(count,curr_tile%part_x, &
          curr_tile%part_z, curr_tile%part_ux,curr_tile%part_uy, &
          curr_tile%part_uz,curr_tile%part_gaminv,dtt)
                    
        END DO! END LOOP ON SPECIES
      ENDIF
    END DO
  END DO! END LOOP ON TILES
  !$OMP END PARALLEL DO

#if PROFILING==3            
  CALL stop_collection()    
#endif                      

  tend=MPI_WTIME()
  pushtime=pushtime+(tend-tdeb)
  localtimes(1) = localtimes(1) + (tend-tdeb)
END SUBROUTINE field_gathering_plus_particle_pusher_sub_2d