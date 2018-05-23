
#pragma once

#include "inject.hxx"
#include "cuda_iface.h"
#include "fields_item_moments_1st_cuda.hxx"

// ======================================================================
// InjectCuda

template<typename BS, typename Target_t>
struct InjectCuda : InjectBase
{
  using Self = InjectCuda;
  using fields_t = MfieldsSingle::fields_t;
  using Fields = Fields3d<fields_t>;

  InjectCuda(MPI_Comm comm, int interval, int tau, int kind_n,
	     Target_t target)
    : InjectBase(interval, tau, kind_n),
      target_{target},
      moment_n_{ppsc->grid(), comm}
  {}

  // ----------------------------------------------------------------------
  // dtor

  ~InjectCuda()
  {
    // FIXME, more cleanup needed
  }
  
  // ----------------------------------------------------------------------
  // get_n_in_cell
  //
  // helper function for partition / particle setup FIXME duplicated

  static inline int
  get_n_in_cell(struct psc *psc, struct psc_particle_npt *npt)
  {
    const auto& grid = psc->grid();
    
    if (psc->prm.const_num_particles_per_cell) {
      return psc->prm.nicell;
    }
    if (npt->particles_per_cell) {
      return npt->n * npt->particles_per_cell + .5;
    }
    if (psc->prm.fractional_n_particles_per_cell) {
      int n_prts = npt->n / grid.cori;
      float rmndr = npt->n / grid.cori - n_prts;
      float ran = random() / ((float) RAND_MAX + 1);
      if (ran < rmndr) {
	n_prts++;
      }
      return n_prts;
    }
    return npt->n / grid.cori + .5;
  }

  // FIXME duplicated

  static void
  _psc_setup_particle(struct psc *psc, struct cuda_mparticles_prt *cprt,
		      struct psc_particle_npt *npt, int p, double xx[3])
  {
    const auto& grid = psc->grid();
    const auto& kinds = grid.kinds;
    double beta = grid.beta;

    float ran1, ran2, ran3, ran4, ran5, ran6;
    do {
      ran1 = random() / ((float) RAND_MAX + 1);
      ran2 = random() / ((float) RAND_MAX + 1);
      ran3 = random() / ((float) RAND_MAX + 1);
      ran4 = random() / ((float) RAND_MAX + 1);
      ran5 = random() / ((float) RAND_MAX + 1);
      ran6 = random() / ((float) RAND_MAX + 1);
    } while (ran1 >= 1.f || ran2 >= 1.f || ran3 >= 1.f ||
	     ran4 >= 1.f || ran5 >= 1.f || ran6 >= 1.f);
	      
    double pxi = npt->p[0] +
      sqrtf(-2.f*npt->T[0]/npt->m*sqr(beta)*logf(1.0-ran1)) * cosf(2.f*M_PI*ran2);
    double pyi = npt->p[1] +
      sqrtf(-2.f*npt->T[1]/npt->m*sqr(beta)*logf(1.0-ran3)) * cosf(2.f*M_PI*ran4);
    double pzi = npt->p[2] +
      sqrtf(-2.f*npt->T[2]/npt->m*sqr(beta)*logf(1.0-ran5)) * cosf(2.f*M_PI*ran6);

    if (psc->prm.initial_momentum_gamma_correction) {
      double gam;
      if (sqr(pxi) + sqr(pyi) + sqr(pzi) < 1.) {
	gam = 1. / sqrt(1. - sqr(pxi) - sqr(pyi) - sqr(pzi));
	pxi *= gam;
	pyi *= gam;
	pzi *= gam;
      }
    }
  
    assert(npt->kind >= 0 && npt->kind < kinds.size());
    assert(npt->q == kinds[npt->kind].q);
    assert(npt->m == kinds[npt->kind].m);

    cprt->xi[0] = xx[0] - grid.patches[p].xb[0];
    cprt->xi[1] = xx[1] - grid.patches[p].xb[1];
    cprt->xi[2] = xx[2] - grid.patches[p].xb[2];
    cprt->pxi[0] = pxi;
    cprt->pxi[1] = pyi;
    cprt->pxi[2] = pzi;
    cprt->kind = npt->kind;
    cprt->qni_wni = kinds[npt->kind].q;
  }	      

  // ----------------------------------------------------------------------
  // operator()

  void operator()(MparticlesCuda<BS>& mprts)
  {
    struct psc *psc = ppsc;
    const auto& grid = psc->grid();
    const auto& kinds = grid.kinds;

    float fac = 1. / grid.cori * 
      (interval * psc->dt / tau) / (1. + interval * psc->dt / tau);

    moment_n_.run(mprts);

    MfieldsCuda& mres = moment_n_.result();
    auto& mf_n = mres.get_as<MfieldsSingle>(kind_n, kind_n+1);

    static struct cuda_mparticles_prt *buf;
    static uint buf_n_alloced;
    if (!buf) {
      buf_n_alloced = 1000;
      buf = (struct cuda_mparticles_prt *) calloc(buf_n_alloced, sizeof(*buf));
    }
    uint buf_n_by_patch[psc->n_patches()];

    uint buf_n = 0;
    psc_foreach_patch(psc, p) {
      buf_n_by_patch[p] = 0;
      Fields N(mf_n[p]);
      const int *ldims = psc->grid().ldims;
    
      for (int jz = 0; jz < ldims[2]; jz++) {
	for (int jy = 0; jy < ldims[1]; jy++) {
	  for (int jx = 0; jx < ldims[0]; jx++) {
	    double xx[3] = { .5 * (CRDX(p, jx) + CRDX(p, jx+1)),
			     .5 * (CRDY(p, jy) + CRDY(p, jy+1)),
			     .5 * (CRDZ(p, jz) + CRDZ(p, jz+1)) };
	    // FIXME, the issue really is that (2nd order) particle pushers
	    // don't handle the invariant dim right
	    if (grid.isInvar(0) == 1) xx[0] = CRDX(p, jx);
	    if (grid.isInvar(1) == 1) xx[1] = CRDY(p, jy);
	    if (grid.isInvar(2) == 1) xx[2] = CRDZ(p, jz);

	    if (!target_.is_inside(xx)) {
	      continue;
	    }

	    int n_q_in_cell = 0;
	    for (int kind = 0; kind < kinds.size(); kind++) {
	      struct psc_particle_npt npt = {};
	      if (kind < kinds.size()) {
		npt.kind = kind;
		npt.q    = kinds[kind].q;
		npt.m    = kinds[kind].m;
	      };
	      target_.init_npt(kind, xx, &npt);
	    
	      int n_in_cell;
	      if (kind != psc->prm.neutralizing_population) {
		if (psc->timestep >= 0) {
		  npt.n -= N(kind_n, jx,jy,jz);
		  if (npt.n < 0) {
		    n_in_cell = 0;
		  } else {
		    // this rounds down rather than trying to get fractional particles
		    // statistically right...
		    n_in_cell = npt.n *fac;		}
		} else {
		  n_in_cell = get_n_in_cell(psc, &npt);
		}
		n_q_in_cell += npt.q * n_in_cell;
	      } else {
		// FIXME, should handle the case where not the last population is neutralizing
		assert(psc->prm.neutralizing_population == kinds.size() - 1);
		n_in_cell = -n_q_in_cell / npt.q;
	      }

	      if (buf_n + n_in_cell > buf_n_alloced) {
		buf_n_alloced = 2 * (buf_n + n_in_cell);
		buf = (struct cuda_mparticles_prt *) realloc(buf, buf_n_alloced * sizeof(*buf));
	      }
	      for (int cnt = 0; cnt < n_in_cell; cnt++) {
		_psc_setup_particle(psc, &buf[buf_n + cnt], &npt, p, xx);
		assert(psc->prm.fractional_n_particles_per_cell);
	      }
	      buf_n += n_in_cell;
	      buf_n_by_patch[p] += n_in_cell;
	    }
	  }
	}
      }
    }

    mres.put_as(mf_n, 0, 0);

    mprts.inject_buf(buf, buf_n_by_patch);
  }

  // ----------------------------------------------------------------------
  // run
  
  void run(PscMparticlesBase mprts_base, PscMfieldsBase mflds_base) override
  {
    auto& mprts = mprts_base->get_as<MparticlesCuda<BS>>();
    (*this)(mprts);
    mprts_base->put_as(mprts);
  }
  
private:
  Target_t target_;
  Moment_n_1st_cuda<BS> moment_n_;
};

