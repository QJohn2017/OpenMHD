subroutine set_dt(U,V,vmax,dt,dx,cfl,ix,jx)
!-----------------------------------------------------------------------
!     CFL condition
!-----------------------------------------------------------------------
  implicit none
  include 'param.h'
  real(8), parameter :: dtmin = 1.0d-7
!-----------------------------------------------------------------------
  integer, intent(in) :: ix, jx
  real(8), intent(in) :: U(ix,jx,var1)
  real(8), intent(in) :: V(ix,jx,var2)
  real(8), intent(in) :: dx, cfl
  real(8), intent(out) :: vmax, dt
!-----------------------------------------------------------------------
  integer :: i, j
  integer :: imax, jmax
  real(8) :: B2, f1, f2, vfx, vfy, vtmp

  vmax = 0.d0
  dt   = 99999.d0

  do j=1,jx
  do i=1,ix

     B2  = dot_product( U(i,j,bx:bz), U(i,j,bx:bz) )
     f1 = gamma * V(i,j,pr)

!    fast mode in the X direction
     f2 = 4 * f1 * U(i,j,bx)**2
!     vfx = sqrt( ( (f1+B2) + sqrt( (f1+B2)**2 - f2 )) / ( 2*U(i,j,ro) ))
     vfx = sqrt( ( (f1+B2) + sqrt(max( (f1+B2)**2-f2, 0.d0 ))) / ( 2*U(i,j,ro) ))

!    fast mode in the Y direction
     f2 = 4 * f1 * U(i,j,by)**2
!     vfy = sqrt( ( (f1+B2) + sqrt( (f1+B2)**2 - f2 )) / ( 2*U(i,j,ro) ))
     vfy = sqrt( ( (f1+B2) + sqrt(max( (f1+B2)**2-f2, 0.d0 ))) / ( 2*U(i,j,ro) ))

!    max speed of MHD waves
     vtmp = max( abs( V(i,j,vx) ) + vfx, abs( V(i,j,vy) ) + vfy )

     if( vtmp > vmax ) then
        vmax = vtmp
        imax = i
        jmax = j
     endif
     
  enddo
  enddo

! dt
  dt = cfl * dx / vmax

! error check
  if( dt < dtmin ) then
     write(6,*) ' dt is too small : ', dt, ' < ', dtmin
     write(6,*) '     velocity is : ', vmax
     write(6,*) imax, jmax, U(imax,jmax,ro), V(imax,jmax,pr)
     stop
  endif

  return
end subroutine set_dt
