c THIS SUBROUTINE EXCHANGES PARTICLES IN Z-DIRECTION.
c THE ROUTINE IS CALLED BY PIC_move_part.f. PIC_pex.f, 
c PIC_pey.f, and PIC_pez.f CAN BE INTERCHANGED.


      subroutine PIC_pez

      use PIC_variables
      use VLA_variables

      implicit none
      include './mpif.h'

      character*(5) :: node

      integer :: la,le
      integer :: nodei,nodej,nodek
      integer :: mtag,status(MPI_STATUS_SIZE)

      real(kind=8) :: restk,zs
      real(kind=8) :: zbn,zbx
      real(kind=8) :: xi,yi,zi
      real(kind=8) :: pxi,pyi,pzi
      real(kind=8) :: qni,mni,cni,lni,wni

      real(kind=8) :: s_cpub  
      real(kind=8) :: s_cpud


      s_cpub=0.0d0
      s_cpud=0.0d0


c---------------------------------------------------------------------
c TOPOLOGY AND CONVENTIONS (example of 12 nodes)
c---------------------------------------------------------------------
c  topology:  npe=12
c
c             -------------------------
c             |  2  |  5  |  8  | 11  |
c             -------------------------      
c  x, xnpe=3  |  1  |  4  |  7  | 10  |      0.le.mpe.le.npe-1
c             -------------------------
c             |  0  |  3  |  6  |  9  |
c             -------------------------
C                     y, ynpe=4
c
c
c  transcription:     x, xnpe=4
c
c             -------------------------
c             | 31  | 32  | 33  | 34  |      nodei=seg_i1(mpe)
c             -------------------------      nodej=seg_i2(mpe)      
c  x, xnpe=3  | 21  | 22  | 23  | 24  |
c             -------------------------      1.le.nodei.le.xnpe
c             | 11  | 12  | 13  | 14  |      1.le.nodej.le.ynpe
c             -------------------------
c                     y, ynpe=4
c
C
c  memory on node 7 = node 23:
c
c                         e3              
c  i1mx+rd   -----------------------------
c            | ------------------------- |     
c            | |            (i1mx,i2mx)| |      rd grid points in
c            | |                       | |      each spatial direction
c         e4 | |           7           | | e2   are kept in excess.
c            | |                       | |
c            | |                       | |
c            | |(i1mn,i2mn)            | |
c            | ------------------------- |
c  i1mn-rd   -----------------------------
c                         e1              
c          i2mn-rd                   i2mx+rd
c
c         rd: width of additional data space
c      e1-e4: edge regions of the grid
c
c---------------------------------------------------------------------


c SETUP


      mtag=200

      nodei=seg_i1(mpe)
      nodej=seg_i2(mpe)
      nodek=seg_i3(mpe)

      restk=nodek/2.0-int(nodek/2.0)     ! restj=0.5 => nodej odd


c CALCULATION OF ARRAY SIZE FOR DATA EXCHANGE

! modification of simbox size for particles in z - added by ab
! particles shall not enter pml region

      zbn=i3mn*dz
      zbx=i3mx*dz

      if (nodek.eq.1.and.boundary_pml_z1.ne.'false') then
         zbn=(i3mn+size+1)*dz
      end if
      if (nodek.eq.znpe.and.boundary_pml_z2.ne.'false') then
         zbx=(i3mx-size-1)*dz
      end if


      e5i=0
      e6i=0
      lpi=0

      if (niloc.gt.0) then
         do l=1,niloc

            zi=p_niloc(11*l+2)
            pzi=p_niloc(11*l+5)

            if (zi<zbn) then
               e6i=e6i+1
            else if (zi>zbx) then
               e5i=e5i+1
            else
               lpi=lpi+1
            endif

         enddo
      endif


c LOADING MESSAGE PASSING ARRAYS


      allocate(p_e5i(0:11*e5i+10))
      allocate(p_e6i(0:11*e6i+10))

      lpi=0
      e5i=0
      e6i=0

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

            if (zi<zbn) then
               e6i=e6i+1
               p_e6i(11*e6i)=xi
               p_e6i(11*e6i+1)=yi
               p_e6i(11*e6i+2)=zi
               p_e6i(11*e6i+3)=pxi
               p_e6i(11*e6i+4)=pyi
               p_e6i(11*e6i+5)=pzi
               p_e6i(11*e6i+6)=qni
               p_e6i(11*e6i+7)=mni
               p_e6i(11*e6i+8)=cni
               p_e6i(11*e6i+9)=lni
               p_e6i(11*e6i+10)=wni
            else if (zi>zbx) then
               e5i=e5i+1
               p_e5i(11*e5i)=xi
               p_e5i(11*e5i+1)=yi
               p_e5i(11*e5i+2)=zi
               p_e5i(11*e5i+3)=pxi
               p_e5i(11*e5i+4)=pyi
               p_e5i(11*e5i+5)=pzi
               p_e5i(11*e5i+6)=qni
               p_e5i(11*e5i+7)=mni
               p_e5i(11*e5i+8)=cni
               p_e5i(11*e5i+9)=lni
               p_e5i(11*e5i+10)=wni
            else
               lpi=lpi+1
               p_niloc(11*lpi)=xi
               p_niloc(11*lpi+1)=yi
               p_niloc(11*lpi+2)=zi
               p_niloc(11*lpi+3)=pxi
               p_niloc(11*lpi+4)=pyi
               p_niloc(11*lpi+5)=pzi
               p_niloc(11*lpi+6)=qni
               p_niloc(11*lpi+7)=mni
               p_niloc(11*lpi+8)=cni
               p_niloc(11*lpi+9)=lni
               p_niloc(11*lpi+10)=wni
            endif

         enddo
      endif


C ARRAY DIMENSION EXCHANGE


      call SERV_systime(cpua)
      if (nodek.lt.znpe.and.restk<0.25) then               ! UPDATING e6
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_SSEND(e5i,1,MPI_INTEGER,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (1.lt.nodek.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_RECV(re6i,1,MPI_INTEGER,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif

      if (nodek.lt.znpe.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_SSEND(e5i,1,MPI_INTEGER,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (1.lt.nodek.and.restk<0.25) then
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_RECV(re6i,1,MPI_INTEGER,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif


      if (boundary_part_z==1) then
         if (znpe.gt.1) then                         !PERIODIC CONTINUATION
            if (nodek.eq.znpe) then
               pec=seg_inv(nodei,nodej,1)
               call MPI_SSEND(e5i,1,MPI_INTEGER,
     &                        pec,mtag,MPI_COMM_WORLD,info)
            endif
            if (1.eq.nodek) then
               pec=seg_inv(nodei,nodej,znpe)
               call MPI_RECV(re6i,1,MPI_INTEGER,
     &                       pec,mtag,MPI_COMM_WORLD,status,info)
            endif
         else
            re6i=e5i
         endif
      endif


      if (1.lt.nodek.and.restk<0.25) then               ! UPDATING e5
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_SSEND(e6i,1,MPI_INTEGER,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (nodek.lt.znpe.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_RECV(re5i,1,MPI_INTEGER,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif

      if (1.lt.nodek.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_SSEND(e6i,1,MPI_INTEGER,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (nodek.lt.znpe.and.restk<0.25) then
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_RECV(re5i,1,MPI_INTEGER,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif


      if (boundary_part_z==1) then
         if (znpe.gt.1) then                         !PERIODIC CONTINUATION
            if (1.eq.nodek) then
               pec=seg_inv(nodei,nodej,znpe)
               call MPI_SSEND(e6i,1,MPI_INTEGER,
     &                        pec,mtag,MPI_COMM_WORLD,info)
            endif
            if (nodek.eq.znpe) then
               pec=seg_inv(nodei,nodej,1)
               call MPI_RECV(re5i,1,MPI_INTEGER,
     &                       pec,mtag,MPI_COMM_WORLD,status,info)
            endif
         else
            re5i=e6i
         endif
      endif


c PARTICLE EXCHANGE


      allocate(p_re5i(0:11*re5i+10))
      allocate(p_re6i(0:11*re6i+10))


      zs=(i3x-i3n+1)*dz
c      zs=(i3x-i3n)*dz


      if (nodek.lt.znpe.and.restk<0.25) then               ! UPDATING e6
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_SSEND(p_e5i,11*e5i+11,MPI_DOUBLE_PRECISION,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (1.lt.nodek.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_RECV(p_re6i,11*re6i+11,MPI_DOUBLE_PRECISION,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif

      if (nodek.lt.znpe.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_SSEND(p_e5i,11*e5i+11,MPI_DOUBLE_PRECISION,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (1.lt.nodek.and.restk<0.25) then
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_RECV(p_re6i,11*re6i+11,MPI_DOUBLE_PRECISION,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif


      if (boundary_part_z==1) then
         if (znpe.gt.1) then                       !PERIODIC CONTINUATION
            if (nodek.eq.znpe) then
               pec=seg_inv(nodei,nodej,1)
               call MPI_SSEND(p_e5i,11*e5i+11,MPI_DOUBLE_PRECISION,
     &                        pec,mtag,MPI_COMM_WORLD,info)
            endif
            if (1.eq.nodek) then
               pec=seg_inv(nodei,nodej,znpe)
               call MPI_RECV(p_re6i,11*re6i+11,MPI_DOUBLE_PRECISION,
     &                       pec,mtag,MPI_COMM_WORLD,status,info)
               do l=1,re6i
                  p_re6i(11*l+2)=p_re6i(11*l+2)-zs
               enddo
            endif
         else
            do l=1,re6i
               p_re6i(11*l)=p_e5i(11*l)
               p_re6i(11*l+1)=p_e5i(11*l+1)
               p_re6i(11*l+2)=p_e5i(11*l+2)-zs
               p_re6i(11*l+3)=p_e5i(11*l+3)
               p_re6i(11*l+4)=p_e5i(11*l+4)
               p_re6i(11*l+5)=p_e5i(11*l+5)
               p_re6i(11*l+6)=p_e5i(11*l+6)
               p_re6i(11*l+7)=p_e5i(11*l+7)
               p_re6i(11*l+8)=p_e5i(11*l+8)
               p_re6i(11*l+9)=p_e5i(11*l+9)
               p_re6i(11*l+10)=p_e5i(11*l+10)
            enddo
         endif
      endif


      if (boundary_part_z==0) then
         if (znpe.gt.1) then                       !MIRROR REFLECTION
            if (nodek.eq.znpe) then
               do l=1,e5i
                  lpi=lpi+1
                  p_niloc(11*lpi)=p_e5i(11*l)
                  p_niloc(11*lpi+1)=p_e5i(11*l+1)
                  p_niloc(11*lpi+2)=2.0*zbx-p_e5i(11*l+2)
                  p_niloc(11*lpi+3)=p_e5i(11*l+3)
                  p_niloc(11*lpi+4)=p_e5i(11*l+4)
                  p_niloc(11*lpi+5)=-p_e5i(11*l+5)
                  p_niloc(11*lpi+6)=p_e5i(11*l+6)
                  p_niloc(11*lpi+7)=p_e5i(11*l+7)
                  p_niloc(11*lpi+8)=p_e5i(11*l+8)
                  p_niloc(11*lpi+9)=p_e5i(11*l+9)
                  p_niloc(11*lpi+10)=p_e5i(11*l+10)
               enddo
            endif
         else
            do l=1,e5i
               lpi=lpi+1
               p_niloc(11*lpi)=p_e5i(11*l)
               p_niloc(11*lpi+1)=p_e5i(11*l+1)
               p_niloc(11*lpi+2)=2.0*zbx-p_e5i(11*l+2)
               p_niloc(11*lpi+3)=p_e5i(11*l+3)
               p_niloc(11*lpi+4)=p_e5i(11*l+4)
               p_niloc(11*lpi+5)=-p_e5i(11*l+5)
               p_niloc(11*lpi+6)=p_e5i(11*l+6)
               p_niloc(11*lpi+7)=p_e5i(11*l+7)
               p_niloc(11*lpi+8)=p_e5i(11*l+8)
               p_niloc(11*lpi+9)=p_e5i(11*l+9)
               p_niloc(11*lpi+10)=p_e5i(11*l+10)
            enddo
         endif
      endif


      if (1.lt.nodek.and.restk<0.25) then               ! UPDATING e5
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_SSEND(p_e6i,11*e6i+11,MPI_DOUBLE_PRECISION,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (nodek.lt.znpe.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_RECV(p_re5i,11*re5i+11,MPI_DOUBLE_PRECISION,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif

      if (1.lt.nodek.and.restk>0.25) then
         pec=seg_inv(nodei,nodej,nodek-1)
         call MPI_SSEND(p_e6i,11*e6i+11,MPI_DOUBLE_PRECISION,
     &                  pec,mtag,MPI_COMM_WORLD,info)
      endif
      if (nodek.lt.znpe.and.restk<0.25) then
         pec=seg_inv(nodei,nodej,nodek+1)
         call MPI_RECV(p_re5i,11*re5i+11,MPI_DOUBLE_PRECISION,
     &                 pec,mtag,MPI_COMM_WORLD,status,info)
      endif


      if (boundary_part_z==1) then
         if (znpe.gt.1) then                       !PERIODIC CONTINUATION
            if (1.eq.nodek) then
               pec=seg_inv(nodei,nodej,znpe)
               call MPI_SSEND(p_e6i,11*e6i+11,MPI_DOUBLE_PRECISION,
     &                        pec,mtag,MPI_COMM_WORLD,info)
            endif
            if (nodek.eq.znpe) then
               pec=seg_inv(nodei,nodej,1)
               call MPI_RECV(p_re5i,11*re5i+11,MPI_DOUBLE_PRECISION,
     &                       pec,mtag,MPI_COMM_WORLD,status,info)
               do l=1,re5i
                  p_re5i(11*l+2)=p_re5i(11*l+2)+zs
               enddo
            endif
         else
            do l=1,re5i
               p_re5i(11*l)=p_e6i(11*l)
               p_re5i(11*l+1)=p_e6i(11*l+1)
               p_re5i(11*l+2)=p_e6i(11*l+2)+zs
               p_re5i(11*l+3)=p_e6i(11*l+3)
               p_re5i(11*l+4)=p_e6i(11*l+4)
               p_re5i(11*l+5)=p_e6i(11*l+5)
               p_re5i(11*l+6)=p_e6i(11*l+6)
               p_re5i(11*l+7)=p_e6i(11*l+7)
               p_re5i(11*l+8)=p_e6i(11*l+8)
               p_re5i(11*l+9)=p_e6i(11*l+9)
               p_re5i(11*l+10)=p_e6i(11*l+10)
            enddo
         endif
      endif


      if (boundary_part_z==0) then
         if (znpe.gt.1) then                       !MIRROR REFLECTION
            if (1.eq.nodek) then
               do l=1,e6i
                  lpi=lpi+1
                  p_niloc(11*lpi)=p_e6i(11*l)
                  p_niloc(11*lpi+1)=p_e6i(11*l+1)
                  p_niloc(11*lpi+2)=2.0*zbn-p_e6i(11*l+2)
                  p_niloc(11*lpi+3)=p_e6i(11*l+3)
                  p_niloc(11*lpi+4)=p_e6i(11*l+4)
                  p_niloc(11*lpi+5)=-p_e6i(11*l+5)
                  p_niloc(11*lpi+6)=p_e6i(11*l+6)
                  p_niloc(11*lpi+7)=p_e6i(11*l+7)
                  p_niloc(11*lpi+8)=p_e6i(11*l+8)
                  p_niloc(11*lpi+9)=p_e6i(11*l+9)
                  p_niloc(11*lpi+10)=p_e6i(11*l+10)
               enddo
            endif
         else
            do l=1,e6i
               lpi=lpi+1
               p_niloc(11*lpi)=p_e6i(11*l)
               p_niloc(11*lpi+1)=p_e6i(11*l+1)
               p_niloc(11*lpi+2)=2.0*zbn-p_e6i(11*l+2)
               p_niloc(11*lpi+3)=p_e6i(11*l+3)
               p_niloc(11*lpi+4)=p_e6i(11*l+4)
               p_niloc(11*lpi+5)=-p_e6i(11*l+5)
               p_niloc(11*lpi+6)=p_e6i(11*l+6)
               p_niloc(11*lpi+7)=p_e6i(11*l+7)
               p_niloc(11*lpi+8)=p_e6i(11*l+8)
               p_niloc(11*lpi+9)=p_e6i(11*l+9)
               p_niloc(11*lpi+10)=p_e6i(11*l+10)
            enddo
         endif
      endif


      call SERV_systime(cpub)
      s_cpub=s_cpub+cpub-cpua


c LOCAL PARTICLE ARRAY UPDATE


      deallocate(p_e5i)
      deallocate(p_e6i)


      niloc_n=lpi+re5i+re6i
      if (niloc_n.gt.nialloc) then
         call SERV_labelgen(mpe,node)
         call SERV_systime(cpuc)
         open(11,file=trim(data_out)//'/'//node//'ENLARGE',
     &        access='sequential',form='unformatted')
         do l=0,11*niloc+10,100
            le=min(l+99,11*niloc+10)
            write(11) (p_niloc(la),la=l,le)
         enddo
         close(11)

         nialloc=int(1.2*niloc_n+10)
         deallocate(p_niloc)
         allocate(p_niloc(0:11*nialloc+10))

         open(11,file=trim(data_out)//'/'//node//'ENLARGE',
     &        access='sequential',form='unformatted')
         do l=0,11*niloc+10,100
            le=min(l+99,11*niloc+10)
            read(11) (p_niloc(la),la=l,le)
         enddo
         close(11)
         call SERV_systime(cpud)
         s_cpud=s_cpud+cpud-cpuc
      endif


      niloc=lpi
      if (re5i>0) then
         do l=1,re5i
            niloc=niloc+1
            p_niloc(11*niloc)=p_re5i(11*l)
            p_niloc(11*niloc+1)=p_re5i(11*l+1)
            p_niloc(11*niloc+2)=p_re5i(11*l+2)
            p_niloc(11*niloc+3)=p_re5i(11*l+3)
            p_niloc(11*niloc+4)=p_re5i(11*l+4)
            p_niloc(11*niloc+5)=p_re5i(11*l+5)
            p_niloc(11*niloc+6)=p_re5i(11*l+6)
            p_niloc(11*niloc+7)=p_re5i(11*l+7)
            p_niloc(11*niloc+8)=p_re5i(11*l+8)
            p_niloc(11*niloc+9)=p_re5i(11*l+9)
            p_niloc(11*niloc+10)=p_re5i(11*l+10)
         enddo
      endif

      if (re6i>0) then
         do l=1,re6i
            niloc=niloc+1
            p_niloc(11*niloc)=p_re6i(11*l)
            p_niloc(11*niloc+1)=p_re6i(11*l+1)
            p_niloc(11*niloc+2)=p_re6i(11*l+2)
            p_niloc(11*niloc+3)=p_re6i(11*l+3)
            p_niloc(11*niloc+4)=p_re6i(11*l+4)
            p_niloc(11*niloc+5)=p_re6i(11*l+5)
            p_niloc(11*niloc+6)=p_re6i(11*l+6)
            p_niloc(11*niloc+7)=p_re6i(11*l+7)
            p_niloc(11*niloc+8)=p_re6i(11*l+8)
            p_niloc(11*niloc+9)=p_re6i(11*l+9)
            p_niloc(11*niloc+10)=p_re6i(11*l+10)
         enddo
      endif


      deallocate(p_re5i)
      deallocate(p_re6i)


      cpumess=cpumess+s_cpub
      cpuinou=cpuinou+s_cpud


      end subroutine PIC_pez
