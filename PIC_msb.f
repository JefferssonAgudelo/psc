c THIS SUBROUTINE DETERMINES A 3D SOLUTION OF MAXWELLS EQUATIONS.
c THE UPDATED E AND B-FIELDS ARE AT t=(n+0.5)*dt.


      subroutine PIC_msb

      use PIC_variables
      use VLA_variables

      implicit none

      real(kind=8) :: cnx,cny,cnz
      real(kind=8) :: lx,ly,lz
      real(kind=8) :: jx,jy,jz

      real(kind=8) :: p_pulse_z1
      real(kind=8) :: s_pulse_z1
      real(kind=8) :: p_pulse_z2
      real(kind=8) :: s_pulse_z2
      real(kind=8) :: p_pulse_y1
      real(kind=8) :: s_pulse_y1
      real(kind=8) :: p_pulse_y2
      real(kind=8) :: s_pulse_y2
      real(kind=8) :: p_pulse_x1
      real(kind=8) :: s_pulse_x1
      real(kind=8) :: p_pulse_x2
      real(kind=8) :: s_pulse_x2
      real(kind=8) :: t,x,y,z

      real(kind=8) :: exh,eyh,ezh,bxh,byh,bzh
      real(kind=8) :: exk,eyk,ezk,bxk,byk,bzk

      real(kind=8) :: s_cpub
      real(kind=8) :: s_cpuh


      s_cpub=0.0d0
      s_cpuh=0.0d0
      call SERV_systime(cpug)


c initialization


      lx=dt/dx
      ly=dt/dy
      lz=dt/dz

      cnx=0.5*lx
      cny=0.5*ly
      cnz=0.5*lz


c B-field propagation E^(n+0.5), B^(n+0.5), j^(n+1.0), m^(n+0.5)
c -> E^(n+0.5), B^(n+1.0), j^(n+1.0), m^(n+0.5)


      bx2B=0.0
      do i3=i3mn,i3mx
         do i2=i2mn,i2mx
            do i1=i1mn,i1mx
               bxh=bx(i1,i2,i3)
               bxk=bx(i1,i2,i3)
     &             -cny*(ez(i1,i2+1,i3)-ez(i1,i2,i3))
     &             +cnz*(ey(i1,i2,i3+1)-ey(i1,i2,i3))
               bx2B=bx2B+dx*dy*dz*bxh*bxk
            enddo
         enddo
      enddo
      do i3=i3mn-1,i3mx+1
         do i2=i2mn-1,i2mx+1
            do i1=i1mn-1,i1mx+1
               bx(i1,i2,i3)=bx(i1,i2,i3)
     &                      -cny*(ez(i1,i2+1,i3)-ez(i1,i2,i3))
     &                      +cnz*(ey(i1,i2,i3+1)-ey(i1,i2,i3))
            enddo
         enddo
      enddo

      by2B=0.0
      do i3=i3mn,i3mx
         do i2=i2mn,i2mx
            do i1=i1mn,i1mx
               byh=by(i1,i2,i3)
               byk=by(i1,i2,i3)
     &             -cnz*(ex(i1,i2,i3+1)-ex(i1,i2,i3))
     &             +cnx*(ez(i1+1,i2,i3)-ez(i1,i2,i3))
               by2B=by2B+dx*dy*dz*byh*byk
            enddo
         enddo
      enddo
      do i3=i3mn-1,i3mx+1
         do i2=i2mn-1,i2mx+1
            do i1=i1mn-1,i1mx+1
               by(i1,i2,i3)=by(i1,i2,i3)
     &                      -cnz*(ex(i1,i2,i3+1)-ex(i1,i2,i3))
     &                      +cnx*(ez(i1+1,i2,i3)-ez(i1,i2,i3))
            enddo
         enddo
      enddo

      bz2B=0.0
      do i3=i3mn,i3mx
         do i2=i2mn,i2mx
            do i1=i1mn,i1mx
               bzh=bz(i1,i2,i3)
               bzk=bz(i1,i2,i3)
     &             -cnx*(ey(i1+1,i2,i3)-ey(i1,i2,i3))
     &             +cny*(ex(i1,i2+1,i3)-ex(i1,i2,i3))
               bz2B=bz2B+dx*dy*dz*bzh*bzk
            enddo
         enddo
      enddo
      do i3=i3mn-1,i3mx+1
         do i2=i2mn-1,i2mx+1
            do i1=i1mn-1,i1mx+1
               bz(i1,i2,i3)=bz(i1,i2,i3)
     &                      -cnx*(ey(i1+1,i2,i3)-ey(i1,i2,i3))
     &                      +cny*(ex(i1,i2+1,i3)-ex(i1,i2,i3))
            enddo
         enddo
      enddo


c open boundary at z1 plus incident laser pulse


      if (boundary_field_z==0) then       

      t=n*dt
      i3=i3mn-1
      z=i3*dz

      do i2=i2mn-1,i2mx+1
         y=i2*dy
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jx=jxi(i1,i2,i3)
            by(i1,i2,i3-1)=(+4.0*s_pulse_z1(x+0.5*dx,y,z,t)
     &                      -2.0*ex(i1,i2,i3)
     &                      -(1.0-lz)*by(i1,i2,i3)
     &                      -ly*(bz(i1,i2,i3)-bz(i1,i2-1,i3))
     &                      +dt*jx)/(1.0+lz)
         enddo
      enddo

      t=n*dt
      i3=i3mn-1
      z=i3*dz

      do i2=i2mn-1,i2mx+1
         y=i2*dy
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jy=jyi(i1,i2,i3)
            bx(i1,i2,i3-1)=(-4.0*p_pulse_z1(x,y+0.5*dy,z,t)
     &                      +2.0*ey(i1,i2,i3)
     &                      -(1.0-lz)*bx(i1,i2,i3)
     &                      -lx*(bz(i1,i2,i3)-bz(i1-1,i2,i3))
     &                      -dt*jy)/(1.0+lz)
         enddo
      enddo


c open boundary at z2 plus incident laser pulse


      t=n*dt
      i3=i3mx+1
      z=i3*dz

      do i2=i2mn-1,i2mx+1
         y=i2*dy
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jx=jxi(i1,i2,i3)
            by(i1,i2,i3)=(-4.0*s_pulse_z2(x+0.5*dx,y,z,t)
     &                    +2.0*ex(i1,i2,i3)
     &                    -(1.0-lz)*by(i1,i2,i3-1)
     &                    +ly*(bz(i1,i2,i3)-bz(i1,i2-1,i3))
     &                    -dt*jx)/(1.0+lz)
         enddo
      enddo

      t=n*dt
      i3=i3mx+1
      z=i3*dz

      do i2=i2mn-1,i2mx+1
         y=i2*dy
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jy=jyi(i1,i2,i3)
            bx(i1,i2,i3)=(+4.0*p_pulse_z2(x,y+0.5*dy,z,t)
     &                    -2.0*ey(i1,i2,i3)
     &                    -(1.0-lz)*bx(i1,i2,i3-1)
     &                    +lx*(bz(i1,i2,i3)-bz(i1-1,i2,i3))
     &                    +dt*jy)/(1.0+lz)
         enddo
      enddo
      endif


c open boundary at y1 plus incident laser pulse


      if (boundary_field_y==0) then       

      t=n*dt
      i2=i2mn-1
      y=i2*dy

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jx=jxi(i1,i2,i3)
            bz(i1,i2-1,i3)=(-4.0*s_pulse_y1(x+0.5*dx,y,z,t)
     &                      +2.0*ex(i1,i2,i3)
     &                      -(1.0-ly)*bz(i1,i2,i3)
     &                      -lz*(by(i1,i2,i3)-by(i1,i2,i3-1))
     &                      +dt*jx)/(1.0+ly)
         enddo
      enddo

      t=n*dt
      i2=i2mn-1
      y=i2*dy

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jz=jzi(i1,i2,i3)
            bx(i1,i2-1,i3)=(4.0*p_pulse_y1(x,y,z+0.5*dz,t)
     &                      -2.0*ez(i1,i2,i3)
     &                      -(1.0-ly)*bx(i1,i2,i3)
     &                      -lx*(by(i1,i2,i3)-by(i1-1,i2,i3))
     &                      +dt*jz)/(1.0+ly)
         enddo
      enddo


c open boundary at y2 plus incident laser pulse


      t=n*dt
      i2=i2mx+1
      y=i2*dy

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jx=jxi(i1,i2,i3)
            bz(i1,i2,i3)=(4.0*s_pulse_y2(x+0.5*dx,y,z,t)
     &                    -2.0*ex(i1,i2,i3)
     &                    -(1.0-ly)*bz(i1,i2-1,i3)
     &                    +lz*(by(i1,i2,i3)-by(i1,i2,i3-1))
     &                    -dt*jx)/(1.0+ly)
         enddo
      enddo

      t=n*dt
      i2=i2mx+1
      y=i2*dy

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i1=i1mn-1,i1mx+1
            x=i1*dx
            jz=jzi(i1,i2,i3)
            bx(i1,i2,i3)=(-4.0*p_pulse_y2(x,y,z+0.5*dz,t)
     &                    +2.0*ez(i1,i2,i3)
     &                    -(1.0-ly)*bx(i1,i2-1,i3)
     &                    +lx*(by(i1,i2,i3)-by(i1-1,i2,i3))
     &                    -dt*jz)/(1.0+ly)
         enddo
      enddo
      endif


c open boundary at x1 plus incident laser pulse


      if (boundary_field_x==0) then       

      t=n*dt
      i1=i1mn-1
      x=i1*dx

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i2=i2mn-1,i2mx+1
            y=i2*dy
            jy=jyi(i1,i2,i3)
            bz(i1-1,i2,i3)=(4.0*s_pulse_x1(x,y+0.5*dy,z,t)
     &                      -2.0*ey(i1,i2,i3)
     &                      -(1.0-lx)*bz(i1,i2,i3)
     &                      -lz*(bx(i1,i2,i3)-bx(i1,i2,i3-1))
     &                      -dt*jy)/(1.0+lx)
         enddo
      enddo

      t=n*dt
      i1=i1mn-1
      x=i1*dx

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i2=i2mn-1,i2mx+1
            y=i2*dy
            jz=jzi(i1,i2,i3)
            by(i1-1,i2,i3)=(-4.0*p_pulse_x1(x,y,z+0.5*dz,t)
     &                      +2.0*ez(i1,i2,i3)
     &                      -(1.0-lx)*by(i1,i2,i3)
     &                      +ly*(bx(i1,i2,i3)-bx(i1,i2-1,i3))
     &                      +dt*jz)/(1.0+lx)
         enddo
      enddo


c open boundary at x2 plus incident laser pulse


      t=n*dt
      i1=i1mx+1
      x=i1*dx

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i2=i2mn-1,i2mx+1
            y=i2*dy
            jy=jyi(i1,i2,i3)
            bz(i1,i2,i3)=(-4.0*s_pulse_x2(x,y+0.5*dy,z,t)
     &                      +2.0*ey(i1,i2,i3)
     &                      -(1.0-lx)*bz(i1-1,i2,i3)
     &                      -lz*(bx(i1,i2,i3)-bx(i1,i2,i3-1))
     &                      +dt*jy)/(1.0+lx)
         enddo
      enddo

      t=n*dt
      i1=i1mx+1
      x=i1*dx

      do i3=i3mn-1,i3mx+1
         z=i3*dz
         do i2=i2mn-1,i2mx+1
            y=i2*dy
            jz=jzi(i1,i2,i3)
            by(i1,i2,i3)=(4.0*p_pulse_x2(x,y,z+0.5*dz,t)
     &                      -2.0*ez(i1,i2,i3)
     &                      -(1.0-lx)*by(i1-1,i2,i3)
     &                      +ly*(bx(i1,i2,i3)-bx(i1,i2-1,i3))
     &                      -dt*jz)/(1.0+lx)
         enddo
      enddo
      endif


      call SERV_systime(cpua)
      call PIC_fex(bx)
      call PIC_fey(bx)
      call PIC_fez(bx)
      call PIC_fex(by)
      call PIC_fey(by)
      call PIC_fez(by)
      call PIC_fex(bz)
      call PIC_fey(bz)
      call PIC_fez(bz)
      call SERV_systime(cpub)
      s_cpub=s_cpub+cpub-cpua


c E-field propagation E^(n+0.5), B^(n+1.0), j^(n+1.0) 
c -> E^(n+1.0), B^(n+1.0), j^(n+1.0)


      ex2B=0.0
      do i3=i3mn,i3mx
         do i2=i2mn,i2mx
            do i1=i1mn,i1mx
               jx=jxi(i1,i2,i3)
               exh=ex(i1,i2,i3)
               exk=ex(i1,i2,i3)
     &             +cny*(bz(i1,i2,i3)-bz(i1,i2-1,i3))
     &             -cnz*(by(i1,i2,i3)-by(i1,i2,i3-1))
     &             -0.5*dt*jx
               ex2B=ex2B+dx*dy*dz*exh*exk
            enddo
         enddo
      enddo
      do i3=i3mn-1,i3mx+1
         do i2=i2mn-1,i2mx+1
            do i1=i1mn-1,i1mx+1
               jx=jxi(i1,i2,i3)
               ex(i1,i2,i3)=ex(i1,i2,i3)
     &                       +cny*(bz(i1,i2,i3)-bz(i1,i2-1,i3))
     &                       -cnz*(by(i1,i2,i3)-by(i1,i2,i3-1))
     &                       -0.5*dt*jx
            enddo
         enddo
      enddo

      ey2B=0.0
      do i3=i3mn,i3mx
         do i2=i2mn,i2mx
            do i1=i1mn,i1mx
               jy=jyi(i1,i2,i3)
               eyh=ey(i1,i2,i3)
               eyk=ey(i1,i2,i3)
     &             +cnz*(bx(i1,i2,i3)-bx(i1,i2,i3-1))
     &             -cnx*(bz(i1,i2,i3)-bz(i1-1,i2,i3))
     &             -0.5*dt*jy
               ey2B=ey2B+dx*dy*dz*eyh*eyk
            enddo
         enddo
      enddo
      do i3=i3mn-1,i3mx+1
         do i2=i2mn-1,i2mx+1
            do i1=i1mn-1,i1mx+1
               jy=jyi(i1,i2,i3)
               ey(i1,i2,i3)=ey(i1,i2,i3)
     &                       +cnz*(bx(i1,i2,i3)-bx(i1,i2,i3-1))
     &                       -cnx*(bz(i1,i2,i3)-bz(i1-1,i2,i3))
     &                       -0.5*dt*jy
            enddo
         enddo
      enddo

      ez2B=0.0
      do i3=i3mn,i3mx
         do i2=i2mn,i2mx
            do i1=i1mn,i1mx
               jz=jzi(i1,i2,i3)
               ezh=ez(i1,i2,i3)
               ezk=ez(i1,i2,i3)
     &             +cnx*(by(i1,i2,i3)-by(i1-1,i2,i3))
     &             -cny*(bx(i1,i2,i3)-bx(i1,i2-1,i3))
     &             -0.5*dt*jz
               ez2B=ez2B+dx*dy*dz*ezh*ezk
            enddo
         enddo
      enddo
      do i3=i3mn-1,i3mx+1
         do i2=i2mn-1,i2mx+1
            do i1=i1mn-1,i1mx+1
               jz=jzi(i1,i2,i3)
               ez(i1,i2,i3)=ez(i1,i2,i3)
     &                       +cnx*(by(i1,i2,i3)-by(i1-1,i2,i3))
     &                       -cny*(bx(i1,i2,i3)-bx(i1,i2-1,i3))
     &                       -0.5*dt*jz
            enddo
         enddo
      enddo


      call SERV_systime(cpua)
      call PIC_fex(ex)
      call PIC_fey(ex)
      call PIC_fez(ex)
      call PIC_fex(ey)
      call PIC_fey(ey)
      call PIC_fez(ey)
      call PIC_fex(ez)
      call PIC_fey(ez)
      call PIC_fez(ez)
      call SERV_systime(cpub)
      s_cpub=s_cpub+cpub-cpua


c energy conservation


      do i3=i3mn,i3mx
         do i2=i2mn,i2mx
            do i1=i1mn,i1mx
               jx=jxi(i1,i2,i3)
               jy=jyi(i1,i2,i3)
               jz=jzi(i1,i2,i3)
               je=je+0.5*dx*dy*dz*(jx*ex(i1,i2,i3)
     &                            +jy*ey(i1,i2,i3)
     &                            +jz*ez(i1,i2,i3))
            enddo
         enddo
      enddo


      call SERV_systime(cpuh)
      s_cpuh=s_cpuh+cpuh-cpug


      cpumess=cpumess+s_cpub
      cpucomp=cpucomp+s_cpuh-s_cpub


      end subroutine PIC_msb
