c THIS SUBROUTINE IS THE PARTICLE MOVER.


      subroutine PIC_move_part_xy

      use PIC_variables
      use VLA_variables

      implicit none
      integer :: j1,j2,j3,k1,k2,l1,l2,l3
      integer :: l1min,l1max,l2min,l2max

      real(kind=8) :: dxi,dyi,dzi
      real(kind=8) :: pxi,pyi,pzi
      real(kind=8) :: pxm,pym,pzm,pxp,pyp,pzp
      real(kind=8) :: qni,mni,cni,lni,wni
      real(kind=8) :: xi,yi,zi,vxi,vyi,vzi,root
      real(kind=8) :: xl,yl,zl
      
      real(kind=8) :: dqs,fnqs,fnqxs,fnqys,fnqzs
      real(kind=8) :: dq,fnq,fnqx,fnqy,fnqz

      real(kind=8) :: h1,h2,h3
      real(kind=8) :: hmx,h0x,h1x,hmy,h0y,h1y
      real(kind=8) :: gmx,g0x,g1x,gmy,g0y,g1y
      real(kind=8) :: wx,wy,wz
      real(kind=8) :: exq,eyq,ezq
!      real(kind=8) :: bxq,byq,bzq
      real(kind=8) :: hxq,hyq,hzq
      real(kind=8) :: taux,tauy,tauz,tau
      real(kind=8) :: u,v,w

      real(kind=8) :: s_cpub
      real(kind=8) :: s_cpuh

      real(kind=8),allocatable,dimension(:) :: s0x,s0y


      real(kind=8),allocatable,dimension(:) :: s1x,s1y
      real(kind=8),allocatable,dimension(:,:,:) :: jxh,jyh,jzh


      s_cpub=0.0d0
      s_cpuh=0.0d0
      call SERV_systime(cpug)


      allocate(s0x(-2:2))
      allocate(s0y(-2:2))
      allocate(s1x(-2:2))
      allocate(s1y(-2:2))

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

            xi=xi+vxi*xl
            yi=yi+vyi*yl

            s0x=0.0
            s0y=0.0
            s1x=0.0
            s1y=0.0

            u=xi*dxi
            v=yi*dyi
            w=zi*dzi
            j1=nint(u)
            j2=nint(v)
            j3=nint(w)
            h1=j1-u
            h2=j2-v
            h3=j3-w
            gmx=0.5*(0.5+h1)*(0.5+h1)
            gmy=0.5*(0.5+h2)*(0.5+h2)
            g0x=0.75-h1*h1
            g0y=0.75-h2*h2
            g1x=0.5*(0.5-h1)*(0.5-h1)
            g1y=0.5*(0.5-h2)*(0.5-h2)

            s0x(-1)=0.5*(1.5-abs(h1-1.0))*(1.5-abs(h1-1.0))
            s0x(+0)=0.75-abs(h1)*abs(h1)
            s0x(+1)=0.5*(1.5-abs(h1+1.0))*(1.5-abs(h1+1.0))
            s0y(-1)=0.5*(1.5-abs(h2-1.0))*(1.5-abs(h2-1.0))
            s0y(+0)=0.75-abs(h2)*abs(h2)
            s0y(+1)=0.5*(1.5-abs(h2+1.0))*(1.5-abs(h2+1.0))

            u=xi*dxi-0.5
            v=yi*dyi-0.5
            w=zi*dzi
            l1=nint(u)
            l2=nint(v)
            l3=nint(w)
            h1=l1-u
            h2=l2-v
            h3=l3-w
            hmx=0.5*(0.5+h1)*(0.5+h1)
            hmy=0.5*(0.5+h2)*(0.5+h2)
            h0x=0.75-h1*h1
            h0y=0.75-h2*h2
            h1x=0.5*(0.5-h1)*(0.5-h1)
            h1y=0.5*(0.5-h2)*(0.5-h2)

c     FIELD INTERPOLATION

            exq=gmy*(hmx*ex(l1-1,j2-1,j3)
     &              +h0x*ex(l1,j2-1,j3)
     &              +h1x*ex(l1+1,j2-1,j3))
     &         +g0y*(hmx*ex(l1-1,j2,j3)
     &              +h0x*ex(l1,j2,j3)
     &              +h1x*ex(l1+1,j2,j3))
     &         +g1y*(hmx*ex(l1-1,j2+1,j3)
     &              +h0x*ex(l1,j2+1,j3)
     &              +h1x*ex(l1+1,j2+1,j3))

            eyq=hmy*(gmx*ey(j1-1,l2-1,j3)
     &              +g0x*ey(j1,l2-1,j3)
     &              +g1x*ey(j1+1,l2-1,j3))
     &         +h0y*(gmx*ey(j1-1,l2,j3)
     &              +g0x*ey(j1,l2,j3)
     &              +g1x*ey(j1+1,l2,j3))
     &         +h1y*(gmx*ey(j1-1,l2+1,j3)
     &              +g0x*ey(j1,l2+1,j3)
     &              +g1x*ey(j1+1,l2+1,j3))

            ezq=gmy*(gmx*ez(j1-1,j2-1,l3)
     &              +g0x*ez(j1,j2-1,l3)
     &              +g1x*ez(j1+1,j2-1,l3))
     &         +g0y*(gmx*ez(j1-1,j2,l3)
     &              +g0x*ez(j1,j2,l3)
     &              +g1x*ez(j1+1,j2,l3))
     &         +g1y*(gmx*ez(j1-1,j2+1,l3)
     &              +g0x*ez(j1,j2+1,l3)
     &              +g1x*ez(j1+1,j2+1,l3))

!            bxq=hmy*(gmx*bx(j1-1,l2-1,l3)
!     &              +g0x*bx(j1,l2-1,l3)
!     &              +g1x*bx(j1+1,l2-1,l3))
!     &         +h0y*(gmx*bx(j1-1,l2,l3)
!     &              +g0x*bx(j1,l2,l3)
!     &              +g1x*bx(j1+1,l2,l3))
!     &         +h1y*(gmx*bx(j1-1,l2+1,l3)
!     &              +g0x*bx(j1,l2+1,l3)
!     &              +g1x*bx(j1+1,l2+1,l3))

!            byq=gmy*(hmx*by(l1-1,j2-1,l3)
!     &              +h0x*by(l1,j2-1,l3)
!     &              +h1x*by(l1+1,j2-1,l3))
!     &         +g0y*(hmx*by(l1-1,j2,l3)
!     &              +h0x*by(l1,j2,l3)
!     &              +h1x*by(l1+1,j2,l3))
!     &         +g1y*(hmx*by(l1-1,j2+1,l3)
!     &              +h0x*by(l1,j2+1,l3)
!     &              +h1x*by(l1+1,j2+1,l3))

!            bzq=hmy*(hmx*bz(l1-1,l2-1,j3)
!     &              +h0x*bz(l1,l2-1,j3)
!     &              +h1x*bz(l1+1,l2-1,j3))
!     &         +h0y*(hmx*bz(l1-1,l2,j3)
!     &              +h0x*bz(l1,l2,j3)
!     &              +h1x*bz(l1+1,l2,j3))
!     &         +h1y*(hmx*bz(l1-1,l2+1,j3)
!     &              +h0x*bz(l1,l2+1,j3)
!     &              +h1x*bz(l1+1,l2+1,j3))

            hxq=hmy*(gmx*hx(j1-1,l2-1,l3)
     &              +g0x*hx(j1,l2-1,l3)
     &              +g1x*hx(j1+1,l2-1,l3))
     &         +h0y*(gmx*hx(j1-1,l2,l3)
     &              +g0x*hx(j1,l2,l3)
     &              +g1x*hx(j1+1,l2,l3))
     &         +h1y*(gmx*hx(j1-1,l2+1,l3)
     &              +g0x*hx(j1,l2+1,l3)
     &              +g1x*hx(j1+1,l2+1,l3))

            hyq=gmy*(hmx*hy(l1-1,j2-1,l3)
     &              +h0x*hy(l1,j2-1,l3)
     &              +h1x*hy(l1+1,j2-1,l3))
     &         +g0y*(hmx*hy(l1-1,j2,l3)
     &              +h0x*hy(l1,j2,l3)
     &              +h1x*hy(l1+1,j2,l3))
     &         +g1y*(hmx*hy(l1-1,j2+1,l3)
     &              +h0x*hy(l1,j2+1,l3)
     &              +h1x*hy(l1+1,j2+1,l3))

            hzq=hmy*(hmx*hz(l1-1,l2-1,j3)
     &              +h0x*hz(l1,l2-1,j3)
     &              +h1x*hz(l1+1,l2-1,j3))
     &         +h0y*(hmx*hz(l1-1,l2,j3)
     &              +h0x*hz(l1,l2,j3)
     &              +h1x*hz(l1+1,l2,j3))
     &         +h1y*(hmx*hz(l1-1,l2+1,j3)
     &              +h0x*hz(l1,l2+1,j3)
     &              +h1x*hz(l1+1,l2+1,j3))

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

            xi=xi+vxi*xl
            yi=yi+vyi*yl

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
            h1=l1-u
            h2=l2-v
            h3=l3-w

            gmx=0.5*(1.5-abs(h1-1.0))*(1.5-abs(h1-1.0))
            g0x=0.75-abs(h1)*abs(h1)
            g1x=0.5*(1.5-abs(h1+1.0))*(1.5-abs(h1+1.0))
            gmy=0.5*(1.5-abs(h2-1.0))*(1.5-abs(h2-1.0))
            g0y=0.75-abs(h2)*abs(h2)
            g1y=0.5*(1.5-abs(h2+1.0))*(1.5-abs(h2+1.0))

            if (qni.lt.0.0) then
               fnq=qni*wni*fnqs
               ne(l1-1,l2-1,l3)=ne(l1-1,l2-1,l3)+fnq*gmx*gmy
               ne(l1,l2-1,l3)=ne(l1,l2-1,l3)+fnq*g0x*gmy
               ne(l1+1,l2-1,l3)=ne(l1+1,l2-1,l3)+fnq*g1x*gmy
               ne(l1-1,l2,l3)=ne(l1-1,l2,l3)+fnq*gmx*g0y
               ne(l1,l2,l3)=ne(l1,l2,l3)+fnq*g0x*g0y
               ne(l1+1,l2,l3)=ne(l1+1,l2,l3)+fnq*g1x*g0y
               ne(l1-1,l2+1,l3)=ne(l1-1,l2+1,l3)+fnq*gmx*g1y
               ne(l1,l2+1,l3)=ne(l1,l2+1,l3)+fnq*g0x*g1y
               ne(l1+1,l2+1,l3)=ne(l1+1,l2+1,l3)+fnq*g1x*g1y
            else if (qni.gt.0.0) then
               fnq=qni*wni*fnqs
               ni(l1-1,l2-1,l3)=ni(l1-1,l2-1,l3)+fnq*gmx*gmy
               ni(l1,l2-1,l3)=ni(l1,l2-1,l3)+fnq*g0x*gmy
               ni(l1+1,l2-1,l3)=ni(l1+1,l2-1,l3)+fnq*g1x*gmy
               ni(l1-1,l2,l3)=ni(l1-1,l2,l3)+fnq*gmx*g0y
               ni(l1,l2,l3)=ni(l1,l2,l3)+fnq*g0x*g0y
               ni(l1+1,l2,l3)=ni(l1+1,l2,l3)+fnq*g1x*g0y
               ni(l1-1,l2+1,l3)=ni(l1-1,l2+1,l3)+fnq*gmx*g1y
               ni(l1,l2+1,l3)=ni(l1,l2+1,l3)+fnq*g0x*g1y
               ni(l1+1,l2+1,l3)=ni(l1+1,l2+1,l3)+fnq*g1x*g1y
            else if (qni.eq.0.0) then
               fnq=wni*fnqs
               nn(l1-1,l2-1,l3)=nn(l1-1,l2-1,l3)+fnq*gmx*gmy
               nn(l1,l2-1,l3)=nn(l1,l2-1,l3)+fnq*g0x*gmy
               nn(l1+1,l2-1,l3)=nn(l1+1,l2-1,l3)+fnq*g1x*gmy
               nn(l1-1,l2,l3)=nn(l1-1,l2,l3)+fnq*gmx*g0y
               nn(l1,l2,l3)=nn(l1,l2,l3)+fnq*g0x*g0y
               nn(l1+1,l2,l3)=nn(l1+1,l2,l3)+fnq*g1x*g0y
               nn(l1-1,l2+1,l3)=nn(l1-1,l2+1,l3)+fnq*gmx*g1y
               nn(l1,l2+1,l3)=nn(l1,l2+1,l3)+fnq*g0x*g1y
               nn(l1+1,l2+1,l3)=nn(l1+1,l2+1,l3)+fnq*g1x*g1y
            endif

c CHARGE DENSITY FORM FACTOR AT (n+1.5)*dt 
c x^(n+1), p^(n+1) -> x^(n+1.5), p^(n+1)

            xi=xi+vxi*xl
            yi=yi+vyi*yl

            u=xi*dxi
            v=yi*dyi
            k1=nint(u)
            k2=nint(v)
            h1=k1-u
            h2=k2-v

            s1x(k1-j1-1)=0.5*(1.5-abs(h1-1.0))*(1.5-abs(h1-1.0))
            s1x(k1-j1+0)=0.75-abs(h1)*abs(h1)
            s1x(k1-j1+1)=0.5*(1.5-abs(h1+1.0))*(1.5-abs(h1+1.0))
            s1y(k2-j2-1)=0.5*(1.5-abs(h2-1.0))*(1.5-abs(h2-1.0))
            s1y(k2-j2+0)=0.75-abs(h2)*abs(h2)
            s1y(k2-j2+1)=0.5*(1.5-abs(h2+1.0))*(1.5-abs(h2+1.0))

c CURRENT DENSITY AT (n+1.0)*dt

            s1x=s1x-s0x
            s1y=s1y-s0y

            if (k1==j1) then
               l1min=-1
               l1max=+1
            else if (k1==j1-1) then
               l1min=-2
               l1max=+1
            else if (k1==j1+1) then
               l1min=-1
               l1max=+2
            endif
            if (k2==j2) then
               l2min=-1
               l2max=+1
            else if (k2==j2-1) then
               l2min=-2
               l2max=+1
            else if (k2==j2+1) then
               l2min=-1
               l2max=+2
            endif

            jxh=0.0
            jyh=0.0
            jzh=0.0

            fnqx=qni*wni*fnqxs
            fnqy=qni*wni*fnqys
            fnqz=vzi*qni*wni*fnqs
            do l2=l2min,l2max
               do l1=l1min,l1max
                  wx=s1x(l1)*(s0y(l2)+0.5*s1y(l2))
                  wy=s1y(l2)*(s0x(l1)+0.5*s1x(l1))
                  wz=s0x(l1)*s0y(l2)
     &               +0.5*s1x(l1)*s0y(l2)
     &               +0.5*s0x(l1)*s1y(l2)
     &               +0.3333333333*s1x(l1)*s1y(l2)

                  jxh(l1,l2,0)=jxh(l1-1,l2,0)-fnqx*wx
                  jyh(l1,l2,0)=jyh(l1,l2-1,0)-fnqy*wy
                  jzh(l1,l2,0)=fnqz*wz

                  jxi(j1+l1,j2+l2,j3)=jxi(j1+l1,j2+l2,j3)
     &                                   +jxh(l1,l2,0)
                  jyi(j1+l1,j2+l2,j3)=jyi(j1+l1,j2+l2,j3)
     &                                   +jyh(l1,l2,0)
                  jzi(j1+l1,j2+l2,j3)=jzi(j1+l1,j2+l2,j3)
     &                                   +jzh(l1,l2,0)
               enddo
            enddo

         enddo
      endif

      call SERV_systime(cpua)
      call PIC_fax(jxi)
      call PIC_fay(jxi)
      call PIC_fax(jyi)
      call PIC_fay(jyi)
      call PIC_fax(jzi)
      call PIC_fay(jzi)

      call PIC_fex(jxi)
      call PIC_fey(jxi)
      call PIC_fex(jyi)
      call PIC_fey(jyi)
      call PIC_fex(jzi)
      call PIC_fey(jzi)

      call PIC_fax(ne)
      call PIC_fay(ne)
      call PIC_fax(ni)
      call PIC_fay(ni)
      call PIC_fax(nn)
      call PIC_fay(nn)

      call PIC_fex(ne)
      call PIC_fey(ne)
      call PIC_fex(ni)
      call PIC_fey(ni)
      call PIC_fex(nn)
      call PIC_fey(nn)

      call PIC_pex
      call PIC_pey
      call SERV_systime(cpub)
      s_cpub=s_cpub+cpub-cpua


      deallocate(s0x,s0y)
      deallocate(s1x,s1y)
      deallocate(jxh,jyh,jzh)


      call SERV_systime(cpuh)
      s_cpuh=s_cpuh+cpuh-cpug


      cpumess=cpumess+s_cpub
      cpucomp=cpucomp+s_cpuh-s_cpub


      end subroutine PIC_move_part_xy
