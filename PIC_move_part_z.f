c THIS SUBROUTINE IS THE PARTICLE MOVER.


      subroutine PIC_move_part_z

      use PIC_variables
      use VLA_variables

      implicit none
      integer :: j1,j2,j3,k3,l1,l2,l3
      integer :: l3min,l3max

      real(kind=8) :: dxi,dyi,dzi
      real(kind=8) :: pxi,pyi,pzi
      real(kind=8) :: pxm,pym,pzm,pxp,pyp,pzp
      real(kind=8) :: qni,mni,cni,lni,wni
      real(kind=8) :: xi,yi,zi,vxi,vyi,vzi,root
      real(kind=8) :: xl,yl,zl
      
      real(kind=8) :: dqs,fnqs,fnqxs,fnqys,fnqzs
      real(kind=8) :: dq,fnq,fnqx,fnqy,fnqz

      real(kind=8) :: h3
      real(kind=8) :: hmz,h0z,h1z
      real(kind=8) :: gmz,g0z,g1z
      real(kind=8) :: wx,wy,wz
      real(kind=8) :: exq,eyq,ezq
!      real(kind=8) :: bxq,byq,bzq
      real(kind=8) :: hxq,hyq,hzq
      real(kind=8) :: taux,tauy,tauz,tau
      real(kind=8) :: u,v,w

      real(kind=8) :: s_cpub
      real(kind=8) :: s_cpuh

      real(kind=8),allocatable,dimension(:) :: s0z


      real(kind=8),allocatable,dimension(:) :: s1z
      real(kind=8),allocatable,dimension(:,:,:) :: jxh,jyh,jzh


      s_cpub=0.0d0
      s_cpuh=0.0d0
      call SERV_systime(cpug)


      allocate(s0z(-2:2))
      allocate(s1z(-2:2))

      allocate(jxh(-3:2,-2:2,-2:2))
      allocate(jyh(-2:2,-3:2,-2:2))
      allocate(jzh(-2:2,-2:2,-3:2))


c INITIALIZATION


      xl=0.5*dt
      yl=0.5*dt
      zl=0.5*dt
      dqs=0.5*eta*dt
      fnqs=alpha*alpha*cori/eta
      fnqxs=dx*fnqs/dt
      fnqys=dy*fnqs/dt
      fnqzs=dz*fnqs/dt
      dxi=1.0/dx
      dyi=1.0/dy
      dzi=1.0/dz


      ne=0.0d0
      ni=0.0d0
      nn=0.0d0
      jxi=0.0d0
      jyi=0.0d0
      jzi=0.0d0


      p2A=0.0d0
      p2B=0.0d0


c PARTICLE LOOP


      if (niloc.gt.0) then
         do l=1,niloc

            xi=p_niloc(11*l)
            yi=p_niloc(11*l+1)
            zi=p_niloc(11*l+2)
            pxi=p_niloc(11*l+3)
            pyi=p_niloc(11*l+4)
            pzi=p_niloc(11*l+5)
            qni=p_niloc(11*l+6)
            mni=p_niloc(11*l+7)
            cni=p_niloc(11*l+8)
            lni=p_niloc(11*l+9)
            wni=p_niloc(11*l+10)

c CHARGE DENSITY FORM FACTOR AT (n+0.5)*dt 
c x^n, p^n -> x^(n+0.5), p^n

            root=1.0/dsqrt(1.0+pxi*pxi+pyi*pyi+pzi*pzi)
            vxi=pxi*root
            vyi=pyi*root
            vzi=pzi*root

            p2A=p2A+mni*fnqs*(1.0d0/root-1.0d0)/eta

            zi=zi+vzi*zl

            s0z=0.0
            s1z=0.0

            u=xi*dxi
            v=yi*dyi
            w=zi*dzi
            j1=nint(u)
            j2=nint(v)
            j3=nint(w)
            h3=j3-w
            gmz=0.5*(0.5+h3)*(0.5+h3)
            g0z=0.75-h3*h3
            g1z=0.5*(0.5-h3)*(0.5-h3)

            s0z(-1)=0.5*(1.5-abs(h3-1.0))*(1.5-abs(h3-1.0))
            s0z(+0)=0.75-abs(h3)*abs(h3)
            s0z(+1)=0.5*(1.5-abs(h3+1.0))*(1.5-abs(h3+1.0))

            u=xi*dxi
            v=yi*dyi
            w=zi*dzi-0.5
            l1=nint(u)
            l2=nint(v)
            l3=nint(w)
            h3=l3-w
            hmz=0.5*(0.5+h3)*(0.5+h3)
            h0z=0.75-h3*h3
            h1z=0.5*(0.5-h3)*(0.5-h3)

c     FIELD INTERPOLATION

            exq=gmz*ex(l1,j2,j3-1)
     &          +g0z*ex(l1,j2,j3)
     &          +g1z*ex(l1,j2,j3+1)

            eyq=gmz*ey(j1,l2,j3-1)
     &          +g0z*ey(j1,l2,j3)
     &          +g1z*ey(j1,l2,j3+1)

            ezq=hmz*ez(j1,j2,l3-1)
     &         +h0z*ez(j1,j2,l3)
     &         +h1z*ez(j1,j2,l3+1)

!            bxq=hmz*bx(j1,l2,l3-1)
!     &          +h0z*bx(j1,l2,l3)
!     &          +h1z*bx(j1,l2,l3+1)

!            byq=hmz*by(l1,j2,l3-1)
!     &         +h0z*by(l1,j2,l3)
!     &         +h1z*by(l1,j2,l3+1)

!            bzq=gmz*bz(l1,l2,j3-1)
!     &          +g0z*bz(l1,l2,j3)
!     &          +g1z*bz(l1,l2,j3+1)

            hxq=hmz*hx(j1,l2,l3-1)
     &          +h0z*hx(j1,l2,l3)
     &          +h1z*hx(j1,l2,l3+1)

            hyq=hmz*hy(l1,j2,l3-1)
     &         +h0z*hy(l1,j2,l3)
     &         +h1z*hy(l1,j2,l3+1)

            hzq=gmz*hz(l1,l2,j3-1)
     &          +g0z*hz(l1,l2,j3)
     &          +g1z*hz(l1,l2,j3+1)

c x^(n+0.5), p^n -> x^(n+1.0), p^(n+1.0) 

            dq=qni*dqs/mni
            pxm=pxi+dq*exq
            pym=pyi+dq*eyq
            pzm=pzi+dq*ezq

            root=dq/dsqrt(1.0+pxm*pxm+pym*pym+pzm*pzm)
!            taux=bxq*root
!            tauy=byq*root
!            tauz=bzq*root
            taux=hxq*root
            tauy=hyq*root
            tauz=hzq*root

            tau=1.0/(1.0+taux*taux+tauy*tauy+tauz*tauz)
            pxp=((1.0+taux*taux-tauy*tauy-tauz*tauz)*pxm
     &          +(2.0*taux*tauy+2.0*tauz)*pym
     &          +(2.0*taux*tauz-2.0*tauy)*pzm)*tau
            pyp=((2.0*taux*tauy-2.0*tauz)*pxm
     &          +(1.0-taux*taux+tauy*tauy-tauz*tauz)*pym
     &          +(2.0*tauy*tauz+2.0*taux)*pzm)*tau
            pzp=((2.0*taux*tauz+2.0*tauy)*pxm
     &          +(2.0*tauy*tauz-2.0*taux)*pym
     &          +(1.0-taux*taux-tauy*tauy+tauz*tauz)*pzm)*tau

            pxi=pxp+dq*exq
            pyi=pyp+dq*eyq
            pzi=pzp+dq*ezq

            root=1.0/dsqrt(1.0+pxi*pxi+pyi*pyi+pzi*pzi)
            vxi=pxi*root
            vyi=pyi*root
            vzi=pzi*root

            zi=zi+vzi*zl

            p_niloc(11*l)=xi
            p_niloc(11*l+1)=yi
            p_niloc(11*l+2)=zi
            p_niloc(11*l+3)=pxi
            p_niloc(11*l+4)=pyi
            p_niloc(11*l+5)=pzi

            p2B=p2B+mni*fnqs*(1.0d0/root-1.0d0)/eta

c DETERMINE THE DENSITIES AT t=(n+1.0)*dt

            u=xi*dxi
            v=yi*dyi
            w=zi*dzi
            l1=nint(u)
            l2=nint(v)
            l3=nint(w)
            h3=l3-w

            gmz=0.5*(1.5-abs(h3-1.0))*(1.5-abs(h3-1.0))
            g0z=0.75-abs(h3)*abs(h3)
            g1z=0.5*(1.5-abs(h3+1.0))*(1.5-abs(h3+1.0))

            if (qni.lt.0.0) then
               fnq=qni*wni*fnqs
               ne(l1,l2,l3-1)=ne(l1,l2,l3-1)+fnq*gmz
               ne(l1,l2,l3)=ne(l1,l2,l3)+fnq*g0z
               ne(l1,l2,l3+1)=ne(l1,l2,l3+1)+fnq*g1z
            else if (qni.gt.0.0) then
               fnq=qni*wni*fnqs
               ni(l1,l2,l3-1)=ni(l1,l2,l3-1)+fnq*gmz
               ni(l1,l2,l3)=ni(l1,l2,l3)+fnq*g0z
               ni(l1,l2,l3+1)=ni(l1,l2,l3+1)+fnq*g1z
            else if (qni.eq.0.0) then
               fnq=wni*fnqs
               nn(l1,l2,l3-1)=nn(l1,l2,l3-1)+fnq*gmz
               nn(l1,l2,l3)=nn(l1,l2,l3)+fnq*g0z
               nn(l1,l2,l3+1)=nn(l1,l2,l3+1)+fnq*g1z
            endif

c CHARGE DENSITY FORM FACTOR AT (n+1.5)*dt 
c x^(n+1), p^(n+1) -> x^(n+1.5), p^(n+1)

            zi=zi+vzi*zl

            w=zi*dzi
            k3=nint(w)
            h3=k3-w

            s1z(k3-j3-1)=0.5*(1.5-abs(h3-1.0))*(1.5-abs(h3-1.0))
            s1z(k3-j3+0)=0.75-abs(h3)*abs(h3)
            s1z(k3-j3+1)=0.5*(1.5-abs(h3+1.0))*(1.5-abs(h3+1.0))

c CURRENT DENSITY AT (n+1.0)*dt

            s1z=s1z-s0z

            if (k3==j3) then
               l3min=-1
               l3max=+1
            else if (k3==j3-1) then
               l3min=-2
               l3max=+1
            else if (k3==j3+1) then
               l3min=-1
               l3max=+2
            endif

            jxh=0.0
            jyh=0.0
            jzh=0.0

            fnqx=vxi*qni*wni*fnqs
            fnqy=vyi*qni*wni*fnqs
            fnqz=qni*wni*fnqzs
            do l3=l3min,l3max
               wx=s0z(l3)+0.5*s1z(l3)
               wy=s0z(l3)+0.5*s1z(l3)
               wz=s1z(l3)

               jxh(0,0,l3)=fnqx*wx
               jyh(0,0,l3)=fnqy*wy
               jzh(0,0,l3)=jzh(0,0,l3-1)-fnqz*wz

               jxi(j1,j2,j3+l3)=jxi(j1,j2,j3+l3)
     &                                +jxh(0,0,l3)
               jyi(j1,j2,j3+l3)=jyi(j1,j2,j3+l3)
     &                                +jyh(0,0,l3)
               jzi(j1,j2,j3+l3)=jzi(j1,j2,j3+l3)
     &                                +jzh(0,0,l3)
            enddo

         enddo
      endif

      call SERV_systime(cpua)
      call PIC_faz(jxi)
      call PIC_faz(jyi)
      call PIC_faz(jzi)

      call PIC_fez(jxi)
      call PIC_fez(jyi)
      call PIC_fez(jzi)

      call PIC_faz(ne)
      call PIC_faz(ni)
      call PIC_faz(nn)

      call PIC_fez(ne)
      call PIC_fez(ni)
      call PIC_fez(nn)

      call PIC_pez
      call SERV_systime(cpub)
      s_cpub=s_cpub+cpub-cpua


      deallocate(s0z)
      deallocate(s1z)
      deallocate(jxh,jyh,jzh)


      call SERV_systime(cpuh)
      s_cpuh=s_cpuh+cpuh-cpug


      cpumess=cpumess+s_cpub
      cpucomp=cpucomp+s_cpuh-s_cpub


      end subroutine PIC_move_part_z
