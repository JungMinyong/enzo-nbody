      SUBROUTINE ADJUST
*     
*     
*     Parameter adjustment and energy check.
*     --------------------------------------
*     
      INCLUDE 'common6.h'
      INCLUDE 'timing.h'
#ifdef TT
      include 'tt.h'
#endif
*     INTEGER JHIST,JHISTR
      COMMON/ECHAIN/  ECH
      COMMON/STSTAT/  TINIT,NIR,NIB,NRGL,NKS
*      COMMON/BLKLVL/JHIST(0:NMAX),JHISTR(0:NMAX),JHISTU(0:NMAX)
      SAVE  DTOFF
      DATA  DTOFF /100.0D0/
*     
*     Predict X & XDOT for all particles (except unperturbed pairs).
      CALL XVPRED(IFIRST,NTOT)
*     --03/20/14 22:21-lwang-debug--------------------------------------*
***** Note:------------------------------------------------------------**
c$$$      if(rank.eq.0) then
c$$$      do J = ifirst,ntot
c$$$         rij2=body(j)*(xdot(1,j)**2+xdot(2,j)**2+xdot(3,j)**2)
c$$$         if(rij2.ge.5E-2) then
c$$$            print*,'J',J,'N',name(j),'F',F(1:3,j),'FD',FDOT(1:3,j),
c$$$     &           'm*v2',rij2,'T0',T0(j),'STEP',STEP(J),'m',body(j)
c$$$            call flush(6)
c$$$         end if
c$$$      end do
c$$$      end if
*     --03/20/14 22:21-lwang-end----------------------------------------*
*     
*     ico = ico + 1
*     do 556 i=1,n
*     write(55,100)ico,name(i),(xdot(k,i),k=1,3)
*556   continue
*     100  format(1x,2i5,3f7.2)
*     
*     Obtain the total energy at current time (resolve all KS pairs).
#ifdef PARALLEL
      CALL ENERGY_MPI(.false.)
#else
      CALL ENERGY(.false.)
#endif
*     
*     Initialize c.m. terms.
      DO 10 K = 1,3
         CMR(K) = 0.0D0
         CMRDOT(K) = 0.0D0
 10   CONTINUE
*     
*     Obtain c.m. & angular momentum integrals and Z-moment of inertia.
      AZ = 0.0D0
      ZM = 0.0D0
      ZMASS = 0.0D0
      IF (NSUB.EQ.0) BODY1 = 0.0D0
      DO 20 I = 1,N
         ZMASS = ZMASS + BODY(I)
         DO 15 K = 1,3
            CMR(K) = CMR(K) + BODY(I)*X(K,I)
            CMRDOT(K) = CMRDOT(K) + BODY(I)*XDOT(K,I)
 15      CONTINUE
         RI2 = (X(1,I) - RDENS(1))**2 + (X(2,I) - RDENS(2))**2 +
     &        (X(3,I) - RDENS(3))**2
*     Skip contribution from escapers.
         IF (RI2.GT.4.0*RTIDE**2) GO TO 20
         AZ = AZ + BODY(I)*(X(1,I)*XDOT(2,I) - X(2,I)*XDOT(1,I))
         ZM = ZM + BODY(I)*(X(1,I)**2 + X(2,I)**2)
*     Update the maximum single body mass but skip compact subsystems.
         IF (NSUB.EQ.0) BODY1 = MAX(BODY1,BODY(I))
 20   CONTINUE
*     
*     Form c.m. coordinates & velocities (vectors & scalars).
      DO 25 K = 1,3
         CMR(K) = CMR(K)/ZMASS
         CMRDOT(K) = CMRDOT(K)/ZMASS
 25   CONTINUE
*     
      CMR(4) = SQRT(CMR(1)**2 + CMR(2)**2 + CMR(3)**2)
      CMRDOT(4) = SQRT(CMRDOT(1)**2 + CMRDOT(2)**2 + CMRDOT(3)**2)
*     
*     Subtract the kinetic energy of c.m. due to possible cloud effects.
      IF (KZ(13).GT.0) ZKIN = ZKIN - 0.5*ZMASS*CMRDOT(4)**2
*     
*       Include non-zero virial energy for Plummer potential and/or 3D case.
      VIR = POT - VIR
*       Note angular momentum term is contained in virial energy (#14=1/2).
      Q = ZKIN/VIR
      E(3) = ZKIN - POT + EPL

*       Modify single particle energy by tidal energy (except pure 3D).
      IF (KZ(14).NE.3.AND.KZ(14).NE.9) THEN
          E(3) = E(3) + ETIDE
      END IF

*       Modify angular momentum integral using Chandrasekhar eq. (5.530).
      IF (KZ(14).EQ.1.OR.KZ(14).EQ.2) THEN
          AZ = AZ + 0.5*TIDAL(4)*ZM
      END IF
*     
*       Define crossing time using single particle energy (cf. option 14).
      TCR = ZMASS**2.5/(2.0*ABS(E(3)))**1.5
*     Define crossing time and save single particle energy.
      IF (Q.GT.1.0.AND.KZ(14).LT.3) THEN
         TCR = TCR*SQRT(2.0*Q)
      END IF
*     Form provisional total energy.
      ETOT = ZKIN - POT + ETIDE + EPL
*     
*     Include KS pairs, triple, quad, mergers, collisions & chain.
      ETOT = ETOT + EBIN + ESUB + EMERGE + ECOLL + EMDOT + ECDOT
      IF (NCH.GT.0) THEN
         ETOT = ETOT + ECH
      END IF
*     Update energies and form the relative error (divide by ZKIN or E(3)).
      IF (TIME.LE.0.0D0) THEN
         DE = 0.0D0
         BE(1) = ETOT
         BE(3) = ETOT
         DELTA1 = 0.0D0
      ELSE
         BE(2) = BE(3)
         BE(3) = ETOT
         DE = BE(3) - BE(2)
         DELTA1 = DE
         DETOT = DETOT + DE
         DE = DE/MAX(ZKIN,ABS(E(3)))
*     Save sum of relative energy error for main output and accumulate DE.
         ERROR = ERROR + DE
         ERRTOT = ERRTOT + DE
      END IF
*     
*     Set provisional half-mass radius.
      RSCALE = 0.5*ZMASS**2/POT
*     
*     Determine average neighbour number and smallest neighbour sphere.
      NNB = 0
      RS0 = RSCALE
      DO 40 I = IFIRST,NTOT
         NNB = NNB + LIST(1,I)
         IF (LIST(1,I).GT.0) RS0 = MIN(RS0,RS(I))
 40   CONTINUE
*     
*     Set average neighbour number.
      NNB = INT(FLOAT(NNB)/FLOAT(N - NPAIRS))
*     
*     Use current value if minimum neighbour sphere not implemented.
      IF (RSMIN.EQ.0.0D0) RSMIN = RS0
*     
*     Find density centre & core radius (Casertano & Hut, Ap.J. 298, 80).
      IF (N-NPAIRS.GE.20.AND.KZ(29).EQ.0) THEN
         CALL CORE
      ELSE
         NC = N
         ZMC = ZMASS
         RHOD = 1.0
         RHOM = 1.0
         RC = RSCALE
         RC2 = RC**2
         RC2IN = 1.0/RC2
      END IF
*     
*     Check optional sorting of Lagrangian radii & half-mass radius.
      IF (KZ(7).GT.0) THEN
         CALL LAGR(RDENS)
      END IF
*     
*     Scale average & maximum core density by the mean value.
      RHOD = 4.0*TWOPI*RHOD*RSCALE**3/(3.0*ZMASS)
      RHOM = 4.0*TWOPI*RHOM*RSCALE**3/(3.0*ZMASS)
*     
*     Adopt density contrasts of unity for hot system.
      IF (KZ(29).GT.0.AND.ZKIN.GT.POT) THEN
         RHOD = 1.0
         RHOM = 1.0
      END IF
*     
*     Check optional determination of regularization parameters.
      IF (KZ(16).GT.0) THEN
         RMIN0 = RMIN
*     
*     Form close encounter distance from scale factor & density contrast.
         RMIN = 4.0*RSCALE/(FLOAT(N)*RHOD**0.3333)
*     Use harmonic mean to reduce fluctuations (avoid initial value).
         IF (TIME.GT.0.0D0) RMIN = SQRT(RMIN0*RMIN)
*     Impose maximum value for sufficient perturbers.
         RMIN = MIN(RMIN,RSMIN*GMIN**0.3333)
*     Define scaled DTMIN by RMIN & <M> and include ETAI for consistency.
         DTMIN = 0.04*SQRT(ETAI/0.02D0)*SQRT(RMIN**3/BODYM)
*     Specify binding energy per unit mass of hard binary (impose Q = 0.5).
         ECLOSE = 4.0*MAX(ZKIN,ABS(ZKIN - POT))/ZMASS
*     Adopt central velocity as upper limit (avoids large kick velocities).
         IF (2.0*ZKIN/ZMASS.GT.VC**2) ECLOSE = 2.0*VC**2
         IF (Q.GT.0.5) THEN
            ECLOSE = 0.5*ECLOSE/Q
            KSMAG = 0
         END IF
      END IF
*     
*     Check optional modification of DTMIN, ECLOSE & TCR for hot system.
      IF (KZ(29).GT.0.AND.Q.GT.1.0) THEN
         DTMIN = 0.04*SQRT(ETAI/0.02D0)*SQRT(RMIN**3/BODYM)
         SIGMA2 = 2.0*ZKIN/ZMASS
         VP2 = 4.0*BODYM/RMIN
         DTMIN = DTMIN*SQRT((VP2 + SIGMA2/Q)/(VP2 + 2.0D0*SIGMA2))
         ECLOSE = SIGMA2
         TCR = 2.0*RSCALE/SQRT(SIGMA2)
      END IF
*     
*     Set useful scalars for the integrator.
      SMIN = 2.0*DTMIN
      RMIN2 = RMIN**2
      RMIN22 = 4.0*RMIN2
      EBH = -0.5*BODYM*ECLOSE
*     Test of Makino for large steps using STEPJ.
      IF (TIME.LE.0.0D0) STEPJ = 0.01*(60000.0/FLOAT(N))**0.3333
*     Adopt 2*RSMIN for neighbour sphere volume factor in routine REGINT.
      RSFAC = MAX(25.0/TCR,3.0D0*VC/(2.0D0*RSMIN))
*     
c$$$*     Update density contrast factor for neighbour sphere modification.
c$$$      IF (TIME.LE.0.0D0.OR.KZ(40).EQ.0) THEN
c$$$         ALPHA = FLOAT(NNBMAX)*SQRT(0.08D0*RSCALE**3/FLOAT(N-NPAIRS))
c$$$      END IF
c$$$*     Include optional stabilization to increase neighbour number.
c$$$      IF (KZ(40).GT.0.AND.FLOAT(NNB).LT.0.5*NNBMAX) THEN
c$$$         FAC = 1.0 + (0.5*NNBMAX - NNB)/(0.5*FLOAT(NNBMAX))
c$$$         ALPHA = FAC*ALPHA
c$$$      END IF
*     
*     Define tidal radius for isolated system (2*RTIDE used in ESCAPE).
      IF (KZ(14).EQ.0) RTIDE = 10.0*RSCALE
#ifdef TT
*** FlorentR - set the tidal radius
      IF (KZ(14).EQ.9) THEN
         IF(TTMODE.NE.1) THEN
*     Temporary solution, need to be checked in the future
            RTIDE = 10.*RSCALE
         ELSE
            write(6,200) TTOT
 200        format(/,12X,'Time[NB] ',E25.17,
     &           ' Tidal tensor eigenvalues:')
            DO K=1,3
               write(6,210) K,TTEIGEN(K),TTEIGENV(1:3,K),TTRTIDE(K)
 210           format('E',I1,' Eigenvalue: ',E18.10,' vector: ',3E18.10,
     &              ' Tidal radius: ',E18.10)
            END DO
            write(6,22) TTEIGEN(1)+TTEIGEN(2)+TTEIGEN(3),
     &           TTEFF(1,1)+TTEFF(2,2)+TTEFF(3,3)
 22         format('  Trace: tensor ',E12.4,'  eigen ',E12.4)
         END IF
      END IF
*** FRenaud
#endif
*     Redefine the crossing time for 3D cluster orbit or Plummer model.
      IF ((KZ(14).EQ.3.OR.KZ(14).EQ.4).AND.ZKIN.GT.0.0) THEN
         TCR = 2.0*RSCALE/SQRT(2.0*ZKIN/ZMASS)
      END IF
*     NBMAX = MIN(NNBMAX+150,LMAX-5)
*     
*     write(6,57)rank,ttfrc
*     57 FORMAT(' IPE=',I4,' ttfrc=',f9.3)
*     
      call cputim(tt1)
      ttotal = (tt1-ttota)*60.
*     
      if(rank.eq.0)then
*     
*     Print energy diagnostics & KS parameters.
         ICR = INT(TTOT/TCR0)
C     New (Aug.1998) by P.Kroupa: (time also in Myr)
c$$$         WRITE(6,50) rank, TTOT, ttot*tscale, Q, DE, DELTA1, BE(3)-EBIN,
c$$$     &        EBIN,EMERGE
         WRITE(6,50) TTOT, ttot*tscale, Q, DE, DELTA1,DETOT, E(3),
     &        ZKIN, POT, ETIDE,
     &        BE(3),EBIN,EMERGE,ESUB,ECOLL,EMDOT,ECDOT
 50      FORMAT (/,' ADJUST:  TIME',1P,D15.5,0P,'  T[Myr]',
     &        F8.2,'  Q',F5.2,'  DE',1P,E12.3,' DELTA',E12.3,
     &        ' DETOT',E12.3,' E',E12.3,' EKIN',E12.3,' POT',E12.3,
     &        ' ETIDE',E12.3,' ETOT', E12.3,
     &        ' EBIN',E12.3,' EMERGE',E12.3,' ESUB',E12.3, 
     &        ' ECOLL',E12.3,' EMDOT',E12.3,' ECDOT',E12.3)
*     
         write(6,51) RMIN, DTMIN, RHOM, RSCALE, RSMIN, ECLOSE, ICR
 51      FORMAT (/, '  RMIN =',1PE8.1,'  DTMIN =',E8.1,' RHOM =',E8.1,
     &        ' RSCALE =',E8.1,' RSMIN =',E8.1,'  ECLOSE =',
     &        0PF5.2,'  TC =',I5)
*     
         WRITE(6,55)
 55      FORMAT('  PE       N        Total     Inti.    Intgrt',
     &        '      Reg.      Irr.     Pred.   Init.B.      Mdot',
     &        '      Move   Comm.I.   Comm.R.   Send.I.   Send.R.',
     &        '        KS    Adjust     OUT      Barr.   Barr.I.   ',
     &        'Barr.R. Reg.GPU.S Reg.GPU.P Comm.Adj.',
     &        ' Mdot.Fic.  Mdot.Fc. Mdot.Pot.  Mdot.EC.   Sort.B.',
     &        '    HighV  KS.Init.B',
     &        '  KS.Int.S  KS.Int.P  KS.Comm.  KS.Barr.   KS.Move',
     &        '   KS.Cmb. KS.Insert  KS.Init.  KS.Term.     Hiar.',
     &        '     KS.UP   KS.TP      xtsub1       xtsub2')
         WRITE(6,56)isize,n,ttotal,ttinitial,ttint,ttreg,ttirr,ttpre,
     &        ttintb,ttmdot,ttmov,ttsub,ttsub2,ttsimdsend,ttgrcomm,
     &        ttks,ttadj,ttout,ttbar,ttbarnb,ttbarreg,ttgrcalc,
     &        ttgrcalc2,ttsube,ttfic,ttfc,ttpot,ttecor,ttnewt,ttshk,
     &        ttksblist,ttksints,ttksintp,ttkssub,ttksbar,ttkscp,
     &        ttkscmb,ttksins,ttksinit,ttksterm,tttq,ttup,tttp,
     &        xtsub1,xtsub2
 56      FORMAT(1X,I3,I8,F13.5,40F10.2,1P,2D13.5)
         CALL FLUSH(6)
      end if

#ifdef GPU      
*     GPU profile
      call gpunb_profile(rank)
*      call gpupot_mdot_profile(rank)
#endif
#ifdef SIMD
*     AVX/SSE profile
      call irr_simd_profile(rank)
#endif      
*     
*     Perform automatic error control (RETURN on restart with KZ(2) > 1).
      CALL CHECK(DE)
      IF (ABS(DE).GT.5.0*QE) GO TO 70
*     
*     Check for escaper removal.
      IF (KZ(23).GT.0) THEN
         CALL ESCAPE
      END IF
*     
*     Check correction for c.m. displacements.
      IF (KZ(31).GT.0) THEN
         CALL CMCORR
      END IF
*     
*     See whether standard output is due.
      IF (TIME.GE.TNEXT) THEN
         CALL OUTPUT
*     
*     Include optional diagnostics for the hardest binary below ECLOSE.
         IF (KZ(9).EQ.1.OR.KZ(9).EQ.3) THEN
            HP = 0.0
            IP = 0
            DO 60 IPAIR = 1,NPAIRS
*     Skip outer (ghost) binary of quadruple system.
               IF (H(IPAIR).LT.HP.AND.BODY(N+IPAIR).GT.0.0D0) THEN
                  HP = H(IPAIR)
                  IP = IPAIR
               END IF
 60         CONTINUE
            IF (IP.GT.0.AND.HP.LT.-ECLOSE) THEN
               I1 = 2*IP - 1
               I2 = I1 + 1
               SEMI = -0.5*BODY(N+IP)/H(IP)
               PB = DAYS*SEMI*SQRT(SEMI/BODY(N+IP))
               ECC2 = (1.0 - R(IP)/SEMI)**2 +
     &              TDOT2(IP)**2/(SEMI*BODY(N+IP))
               EB = BODY(I1)*BODY(I2)*H(IP)/BODY(N+IP)
*               WRITE (39,62)  TTOT, NAME(I1), NAME(I2), KSTAR(N+IP),
*     &              LIST(1,I1), SQRT(ECC2), SEMI, PB, EB, E(3)
* 62            FORMAT (' BINARY:   Time[Myr] NAME(I1) NAME(I2) ',
*     &              'K*(ICM) NP ECC SEMI[NB] P[days] EB[NB] EM[NB] ',
*     &              1P,E26.17,0P,2I12,I4,I6,1P,5E15.6,0P)
*               CALL FLUSH(39)
            END IF
         END IF
*     
      END IF
*     
*     Update time for next adjustment.
      TADJ = TADJ + DTADJ
*     
*     Obtain elapsed CPU time and update total since last output/restart.
      call cputim(tt1)
      CPUTOT = (tt1-ttota)*60.
*     
*     Save COMMON after energy check (skip TRIPLE, QUAD, CHAIN).
      TDUMP = TIME
      IF (KZ(2).GE.1.AND.NSUB.EQ.0) CALL MYDUMP(1,2)
*     
*     Check termination criteria (TIME > TCRIT & N <= NCRIT).
*     
C     New (Aug. 1998): P.Kroupa
*     
      IF (TTOT*TSCALE.GT.TCRITp.OR.TTOT.GT.TCRIT - 20.0*DTMIN
     &     .OR.N.LE.NCRIT) THEN
*     Terminate after optional COMMON save.
         if(rank.eq.0) THEN
*            do k=0,nmax
*               write (666,555) K, JHISTR(k)
* 555           format(1X,2I8)
*            end do
            WRITE (6,65) TTOT*TSCALE, TOFF, TIME, TIME+TOFF,
     &           CPUTOT/60.0,ERRTOT, DETOT
 65         FORMAT (//,9X,'END RUN',3X,' TIME[Myr] =',F8.2,
     &           '  TOFF/TIME/TTOT=',3F16.8, 
     &           '  CPUTOT =',F7.1,
     &           '  ERRTOT =',1P,D12.5,'  DETOT =',D12.5)
         END IF
*     
*     Determine time interval and step numbers per time unit
         TIMINT = TIME + TOFF - TINIT
*     
#ifdef PARALLEL
         IF(rank.EQ.0)THEN
#endif
            WRITE (6,195)  rank,TIMINT,NSTEPI-NIR,NSTEPB-NIB,
     &           NSTEPR-NRGL,NSTEPU-NKS
 195        FORMAT (//,I9,' INTEGRATION INTERVAL =',F8.2,3X,' NIRR='
     &           ,I11,' NIRRB=',I11,' NREG=',I11,' NKS=',I11)
            WRITE (6,196)  (NSTEPI-NIR)/TIMINT,(NSTEPB-NIB)/TIMINT,
     &           (NSTEPR-NRGL)/TIMINT,(NSTEPU-NKS)/TIMINT
 196        FORMAT (//,9X,' PER TIME UNIT: NIRR=',1P,D12.5,' NIRRB=',
     &           D12.5,' NREG=',D12.5,' NKS=',D12.5)
#ifdef PARALLEL
         END IF
#endif
*     
         IF (KZ(1).GT.0) CALL MYDUMP(1,1)
         call cputim(tt1)

#ifdef GPU
         CALL GPUNB_CLOSE
#endif
#ifdef SIMD
         CALL IRR_SIMD_CLOSE(rank)
#endif

#ifdef PARALLEL
         IF(rank.EQ.0)THEN
#endif
           ttotal=(tt1-ttota)*60.
           PRINT*,' Total CPU=',ttotal

           IPHASE = 13

*           by YS Jo to reset variables
           CALL GPUNB_RETURN()
             
*           by sykim to reset count
           CALL RESET_COUNT

#ifdef PARALLEL
         END IF
         call cputim(tt998)
         CALL MPI_BARRIER(MPI_COMM_WORLD,ierr)
         call cputim(tt999)
         ibarcount=ibarcount+1
         ttbar = ttbar + (tt999-tt998)*60
*         CALL MPI_ABORT(MPI_COMM_WORLD,ierr)
         CALL MPI_FINALIZE
#endif

         RETURN
*     
       END IF
*     
*     Check optional truncation of time.
      IF (KZ(35).GT.0.AND.TIME.GE.DTOFF) THEN
         CALL OFFSET(DTOFF)
      END IF
*     
 70   RETURN
*     
      END
