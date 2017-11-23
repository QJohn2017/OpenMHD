program main
!-----------------------------------------------------------------------
!     OpenMHD  Riemann solver (parallel version)
!-----------------------------------------------------------------------
!     2010/09/27  S. Zenitani  K-H instability
!     2010/09/27  S. Zenitani  K-H instability (MPI version)
!     2015/04/05  S. Zenitani  MPI-IO
!-----------------------------------------------------------------------
  implicit none
  include 'mpif.h' ! for MPI
  include 'param.h'
  integer, parameter :: ix = 120 + 2  ! 120 (cells per core) x 4 (cores) = 480
  integer, parameter :: jx = 600 + 2
  integer, parameter :: loop_max = 200000
  real(8), parameter :: tend  = 100.0d0
  real(8), parameter :: dtout =   5.0d0 ! output interval
  real(8), parameter :: cfl   =   0.4d0 ! time step
  integer, parameter :: n_start = 0     ! If non-zero, load previous data file
! Slope limiter  (0: flat, 1: minmod, 2: MC, 3: van Leer, 4: Koren)
  integer, parameter :: lm_type   = 1
! Numerical flux (0: LLF, 1: HLL, 2: HLLC, 3: HLLD)
  integer, parameter :: flux_type = 3
! Time marching  (0: TVD RK2, 1: RK2)
  integer, parameter :: time_type = 0
! File I/O  (0: Standard, 1: MPI-IO)
  integer, parameter :: io_type   = 1
!-----------------------------------------------------------------------
! See also modelp.f90
!-----------------------------------------------------------------------
  integer :: k
  integer :: n_output
  real(8) :: t, dt, t_output
  real(8) :: ch
  character*256 :: filename
  integer :: merr, myrank, npe          ! for MPI
!-----------------------------------------------------------------------
  real(8) :: x(ix), y(jx), dx
  real(8) :: U(ix,jx,var1)  ! conserved variables (U)
  real(8) :: U1(ix,jx,var1) ! conserved variables: medium state (U*)
  real(8) :: V(ix,jx,var2)  ! primitive variables (V)
  real(8) :: VL(ix,jx,var1), VR(ix,jx,var1) ! interpolated states
  real(8) :: F(ix,jx,var1), G(ix,jx,var1)   ! numerical flux (F,G)
!-----------------------------------------------------------------------

!-----------------------------------------------------------------------
! for MPI
  call mpi_init(merr)
  call mpi_comm_size(mpi_comm_world,npe   ,merr)
  call mpi_comm_rank(mpi_comm_world,myrank,merr)
!-----------------------------------------------------------------------

  t    =  0.d0
  dt   =  0.d0
  call modelp(U,V,x,y,dx,ix,jx,myrank,npe)
!    boundary conditions
  call mpibc(U,ix,jx,myrank,npe)
  call set_dt(U,V,ch,dt,dx,cfl,ix,jx)

  call mpi_allreduce(mpi_in_place,dt,1,mpi_double_precision, &
       mpi_min,mpi_comm_world,merr)
  call mpi_allreduce(mpi_in_place,ch,1,mpi_double_precision, &
       mpi_max,mpi_comm_world,merr)
  call mpi_barrier(mpi_comm_world,merr)

  if ( dt .gt. dtout ) then
     write(6,*) 'error: ', dt, '>', dtout
     stop
  endif
  if( myrank.eq.0 ) then
     write(6,*) '[Params]'
     write(6,*) 'Code version: ', version, '  MPI node # : ', npe
     write(6,998) dt, dtout, npe*(ix-2)+2, ix, jx
     write(6,999) lm_type, flux_type, time_type
998  format (' dt: ',e10.3,' dtout: ',e10.3,' grids:',i6,' (',i5,') x ',i5 )
999  format (' limiter: ', i1, '  flux: ', i1, '  time-marching: ', i1 )
     write(6,*) '== start =='
  endif
  call mpi_barrier(mpi_comm_world,merr)

  if ( n_start .ne. 0 ) then
     if ( io_type .eq. 0 ) then
        write(6,*) 'reading data ...   rank = ', myrank
        write(filename,990) myrank, n_start
        call input(filename,ix,jx,t,x,y,U)
     else
        if( myrank.eq.0 )  write(6,*) 'reading data ...'
        write(filename,980) n_start
        call mpiinput(filename,ix,jx,t,x,y,U,myrank,npe)
     endif
  endif
  t_output = t - dt/3.d0
  n_output = n_start

!-----------------------------------------------------------------------
  do k=1,loop_max

     if( myrank.eq.0 ) then
        write(6,*) ' t = ', t
     endif
!    Recovering primitive variables
!     write(6,*) 'U --> V'
     call u2v(U,V,ix,jx)
!   -----------------  
!    [ output ]
     if ( t .ge. t_output ) then
        if (( k .eq. 1 ).and.( n_start .ne. 0 )) then
!           if ( io_type .eq. 0 ) then
!              write(filename,991) myrank, n_start
!              call output(filename,ix,jx,t,x,y,U,V)
!           else
!              write(filename,981) n_output
!              call mpioutput(filename,ix,jx,t,x,y,U,V,myrank,npe)
!           endif
        else
           if ( io_type .eq. 0 ) then
              write(6,*) 'writing data ...   t = ', t, ' rank = ', myrank
              write(filename,990) myrank, n_output
              call output(filename,ix,jx,t,x,y,U,V)
           else
              if( myrank.eq.0 )  write(6,*) 'writing data ...   t = ', t
              write(filename,980) n_output
              call mpioutput(filename,ix,jx,t,x,y,U,V,myrank,npe)
           endif
        endif
        n_output = n_output + 1
        t_output = t_output + dtout
        call mpi_barrier(mpi_comm_world,merr)
     endif
!    [ end? ]
     if ( t .ge. tend )  exit
     if ( k .eq. loop_max ) then
        write(6,*) 'max loop'
        exit
     endif
!   -----------------  
!    CFL condition
     call set_dt(U,V,ch,dt,dx,cfl,ix,jx)
     call mpi_allreduce(mpi_in_place,dt,1,mpi_double_precision, &
          mpi_min,mpi_comm_world,merr)
     call mpi_allreduce(mpi_in_place,ch,1,mpi_double_precision, &
          mpi_max,mpi_comm_world,merr)

!    GLM solver for the first half timestep
!    This should be done after set_dt()
!     write(6,*) 'U --> SS'
     call glm_ss(U,ch,0.5d0*dt,ix,jx)

!    Slope limiters on primitive variables
!     write(6,*) 'V --> VL, VR (F)'
     call limiter(V(1,1,vx),VL(1,1,vx),VR(1,1,vx),ix,jx,1,lm_type)
     call limiter(V(1,1,vy),VL(1,1,vy),VR(1,1,vy),ix,jx,1,lm_type)
     call limiter(V(1,1,vz),VL(1,1,vz),VR(1,1,vz),ix,jx,1,lm_type)
     call limiter(V(1,1,pr),VL(1,1,pr),VR(1,1,pr),ix,jx,1,lm_type)
     call limiter(U(1,1,ro),VL(1,1,ro),VR(1,1,ro),ix,jx,1,lm_type)
     call limiter(U(1,1,bx),VL(1,1,bx),VR(1,1,bx),ix,jx,1,lm_type)
     call limiter(U(1,1,by),VL(1,1,by),VR(1,1,by),ix,jx,1,lm_type)
     call limiter(U(1,1,bz),VL(1,1,bz),VR(1,1,bz),ix,jx,1,lm_type)
     call limiter(U(1,1,ps),VL(1,1,ps),VR(1,1,ps),ix,jx,1,lm_type)
!     write(6,*) 'fix VL/VR at MPI boundary'
     call mpibc_vlvr_f(VL,VR,ix,jx,myrank,npe)
!    Numerical flux in the X direction (F)
!     write(6,*) 'VL, VR --> F'
     call flux_solver(F,VL,VR,ix,jx,1,flux_type)
     call flux_glm(F,VL,VR,ch,ix,jx,1)

!    Slope limiters on primitive variables
!     write(6,*) 'V --> VL, VR (G)'
     call limiter(V(1,1,vx),VL(1,1,vx),VR(1,1,vx),ix,jx,2,lm_type)
     call limiter(V(1,1,vy),VL(1,1,vy),VR(1,1,vy),ix,jx,2,lm_type)
     call limiter(V(1,1,vz),VL(1,1,vz),VR(1,1,vz),ix,jx,2,lm_type)
     call limiter(V(1,1,pr),VL(1,1,pr),VR(1,1,pr),ix,jx,2,lm_type)
     call limiter(U(1,1,ro),VL(1,1,ro),VR(1,1,ro),ix,jx,2,lm_type)
     call limiter(U(1,1,bx),VL(1,1,bx),VR(1,1,bx),ix,jx,2,lm_type)
     call limiter(U(1,1,by),VL(1,1,by),VR(1,1,by),ix,jx,2,lm_type)
     call limiter(U(1,1,bz),VL(1,1,bz),VR(1,1,bz),ix,jx,2,lm_type)
     call limiter(U(1,1,ps),VL(1,1,ps),VR(1,1,ps),ix,jx,2,lm_type)
!    fix VR/VL for wall bc (G)
     call bc_vlvr_g(VL,VR,ix,jx)
!    Numerical flux in the Y direction (G)
!     write(6,*) 'VL, VR --> G'
     call flux_solver(G,VL,VR,ix,jx,2,flux_type)
     call flux_glm(G,VL,VR,ch,ix,jx,2)

     if( time_type .eq. 0 ) then
!       write(6,*) 'U* = U + (dt/dx) (F-F)'
        call rk21(U,U1,F,G,dt,dx,ix,jx)
     elseif( time_type .eq. 1 ) then
!       write(6,*) 'U*(n+1/2) = U + (0.5 dt/dx) (F-F)'
        call step1(U,U1,F,G,dt,dx,ix,jx)
     endif
!    boundary conditions
     call mpibc(U1,ix,jx,myrank,npe)
!     write(6,*) 'U* --> V'
     call u2v(U1,V,ix,jx)

!    Slope limiters on primitive variables
!     write(6,*) 'V --> VL, VR (F)'
     call limiter(V(1,1,vx),VL(1,1,vx),VR(1,1,vx),ix,jx,1,lm_type)
     call limiter(V(1,1,vy),VL(1,1,vy),VR(1,1,vy),ix,jx,1,lm_type)
     call limiter(V(1,1,vz),VL(1,1,vz),VR(1,1,vz),ix,jx,1,lm_type)
     call limiter(V(1,1,pr),VL(1,1,pr),VR(1,1,pr),ix,jx,1,lm_type)
     call limiter(U1(1,1,ro),VL(1,1,ro),VR(1,1,ro),ix,jx,1,lm_type)
     call limiter(U1(1,1,bx),VL(1,1,bx),VR(1,1,bx),ix,jx,1,lm_type)
     call limiter(U1(1,1,by),VL(1,1,by),VR(1,1,by),ix,jx,1,lm_type)
     call limiter(U1(1,1,bz),VL(1,1,bz),VR(1,1,bz),ix,jx,1,lm_type)
     call limiter(U1(1,1,ps),VL(1,1,ps),VR(1,1,ps),ix,jx,1,lm_type)
!     write(6,*) 'fix VL, VR at MPI boundary'
     call mpibc_vlvr_f(VL,VR,ix,jx,myrank,npe)
!    Numerical flux in the X direction (F)
!     write(6,*) 'VL, VR --> F'
     call flux_solver(F,VL,VR,ix,jx,1,flux_type)
     call flux_glm(F,VL,VR,ch,ix,jx,1)

!    Slope limiters on primitive variables
!     write(6,*) 'V --> VL, VR (G)'
     call limiter(V(1,1,vx),VL(1,1,vx),VR(1,1,vx),ix,jx,2,lm_type)
     call limiter(V(1,1,vy),VL(1,1,vy),VR(1,1,vy),ix,jx,2,lm_type)
     call limiter(V(1,1,vz),VL(1,1,vz),VR(1,1,vz),ix,jx,2,lm_type)
     call limiter(V(1,1,pr),VL(1,1,pr),VR(1,1,pr),ix,jx,2,lm_type)
     call limiter(U1(1,1,ro),VL(1,1,ro),VR(1,1,ro),ix,jx,2,lm_type)
     call limiter(U1(1,1,bx),VL(1,1,bx),VR(1,1,bx),ix,jx,2,lm_type)
     call limiter(U1(1,1,by),VL(1,1,by),VR(1,1,by),ix,jx,2,lm_type)
     call limiter(U1(1,1,bz),VL(1,1,bz),VR(1,1,bz),ix,jx,2,lm_type)
     call limiter(U1(1,1,ps),VL(1,1,ps),VR(1,1,ps),ix,jx,2,lm_type)
!    fix VR/VL for wall bc (G)
     call bc_vlvr_g(VL,VR,ix,jx)
!    Numerical flux in the Y direction (G)
!     write(6,*) 'VL, VR --> G'
     call flux_solver(G,VL,VR,ix,jx,2,flux_type)
     call flux_glm(G,VL,VR,ch,ix,jx,2)

     if( time_type .eq. 0 ) then
!       write(6,*) 'U_new = 0.5( U_old + U* + F dt )'
        call rk22(U,U1,F,G,dt,dx,ix,jx)
     elseif( time_type .eq. 1 ) then
!       write(6,*) 'U_new = U + (dt/dx) (F-F) (n+1/2)'
        call step2(U,F,G,dt,dx,ix,jx)
     endif

!    GLM solver for the second half timestep
     call glm_ss(U,ch,0.5d0*dt,ix,jx)

!    boundary condition
     call mpibc(U,ix,jx,myrank,npe)
     t=t+dt

  enddo
!-----------------------------------------------------------------------

  call mpi_finalize(merr)
  if( myrank.eq.0 )  write(6,*) '== end =='

980 format ('data/field-',i5.5,'.dat')
990 format ('data/field-rank',i4.4,'-',i5.5,'.dat')
!981 format ('data/field-',i5.5,'.dat.restart')
!991 format ('data/field-rank',i4.4,'-',i5.5,'.dat.restart')

end program main
!-----------------------------------------------------------------------
