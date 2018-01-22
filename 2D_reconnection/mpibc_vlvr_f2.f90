subroutine mpibc_vlvr_f2(VL,VR,ix,jx,myrank,npe)
!-----------------------------------------------------------------------
!     2010/01/27  S. Zenitani   MPI ex for HLL
!-----------------------------------------------------------------------
  implicit none
  include 'mpif.h'
  include 'param.h'
  integer, intent(in) :: ix, jx, myrank, npe
! left flux (VL) [input]
  real(8) :: VL(ix,jx,var1)
! right flux (VR) [input]
  real(8) :: VR(ix,jx,var1)

  integer :: mstatus(mpi_status_size)
  integer :: mmx, merr, mright, mleft
  real(8) :: bufsnd(jx,var1), bufrcv(jx,var1)

  mmx = jx*var1

!----------------------------------------------------------------------
!  from PE(myrank) to PE(myrank-1) for new da(ix)
!----------------------------------------------------------------------

  mright = myrank+1
  mleft  = myrank-1
  if( myrank == npe-1 )  mright = mpi_proc_null
  if( myrank == 0     )  mleft  = mpi_proc_null

  bufsnd(:,:) = VR(1,:,:)
! call mpi_barrier(mpi_comm_world,merr)
  call mpi_sendrecv( &
       bufsnd,mmx,mpi_real8,mleft ,0, &
       bufrcv,mmx,mpi_real8,mright,0, &
       mpi_comm_world,mstatus,merr)
      
  if( myrank /= npe-1 ) then
     VR(ix-1,:,:) = bufrcv(:,:)
  else
     VR(ix-1,:, ro) =  VL(ix-1,:, ro)
     VR(ix-1,:, vx) = -VL(ix-1,:, vx)
     VR(ix-1,:, vy) =  VL(ix-1,:, vy)
     VR(ix-1,:, vz) = -VL(ix-1,:, vz)
     VR(ix-1,:, pr) =  VL(ix-1,:, pr)
     VR(ix-1,:, bx) =  VL(ix-1,:, bx)
     VR(ix-1,:, by) = -VL(ix-1,:, by)
     VR(ix-1,:, bz) =  VL(ix-1,:, bz)
     VR(ix-1,:, ps) = -VL(ix-1,:, ps)
  endif

!----------------------------------------------------------------------
!  from PE(myrank) to PE(myrank+1) for new da(1)
!----------------------------------------------------------------------

  bufsnd(:,:) = VL(ix-1,:,:)
! call mpi_barrier(mpi_comm_world,merr)
  call mpi_sendrecv( &
       bufsnd,mmx,mpi_real8,mright,1, &
       bufrcv,mmx,mpi_real8,mleft ,1, &
       mpi_comm_world,mstatus,merr)

  if( myrank /= 0 )then
     VL(1,:,:) = bufrcv(:,:)
  else
     VL(1,:, ro) =  VR(1,:, ro)
     VL(1,:, vx) = -VR(1,:, vx)
     VL(1,:, vy) =  VR(1,:, vy)
     VL(1,:, vz) = -VR(1,:, vz)
     VL(1,:, pr) =  VR(1,:, pr)
     VL(1,:, bx) =  VR(1,:, bx)
     VL(1,:, by) = -VR(1,:, by)
     VL(1,:, bz) =  VR(1,:, bz)
     VL(1,:, ps) = -VR(1,:, ps)
  endif
!  call mpi_barrier(mpi_comm_world,merr)

  return
end subroutine mpibc_vlvr_f2
