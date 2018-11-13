
#include "../libpsc/psc_checks/checks_impl.hxx"

#include "pushp_current_esirkepov.hxx"

#define MAX_NR_KINDS (10)

// ======================================================================
// PushParticlesEsirkepov

template<typename C>
struct PushParticlesEsirkepov
{
  using Mparticles = typename C::Mparticles;
  using MfieldsState = typename C::MfieldsState;
  using AdvanceParticle_t = typename C::AdvanceParticle_t;
  using InterpolateEM_t = typename C::InterpolateEM_t;
  using Current = CurrentEsirkepov<typename C::Order, typename C::Dim,
				   Fields3d<typename MfieldsState::fields_t>, InterpolateEM_t>;
  using real_t = typename Mparticles::real_t;
  using Real3 = Vec3<real_t>;

  using checks_order = checks_order_2nd; // FIXME, sometimes 1st even with Esirkepov
  
  static void push_mprts_patch(typename MfieldsState::fields_t flds, typename Mparticles::patch_t& prts)
  {
    typename InterpolateEM_t::fields_t EM(flds);
    typename Current::fields_t J(flds);
    InterpolateEM_t ip;
    AdvanceParticle_t advance(prts.grid().dt);
    Current current(prts.grid());
    
    Real3 dxi = Real3{ 1., 1., 1. } / Real3(prts.grid().domain.dx);
    real_t dq_kind[MAX_NR_KINDS];
    auto& kinds = prts.grid().kinds;
    assert(kinds.size() <= MAX_NR_KINDS);
    for (int k = 0; k < kinds.size(); k++) {
      dq_kind[k] = .5f * prts.grid().norm.eta * prts.grid().dt * kinds[k].q / kinds[k].m;
    }
    
    for (auto& prt: prts) {
      real_t *x = prt.x;
      real_t vv[3];

      real_t xm[3];
      for (int d = 0; d < 3; d++) {
	xm[d] = x[d] * dxi[d];
      }
      ip.set_coeffs(xm);
      
      // CHARGE DENSITY FORM FACTOR AT (n+.5)*dt
      current.charge_before(ip);
      
      // FIELD INTERPOLATION
      real_t E[3] = { ip.ex(EM), ip.ey(EM), ip.ez(EM) };
      real_t H[3] = { ip.hx(EM), ip.hy(EM), ip.hz(EM) };

      // x^(n+0.5), p^n -> x^(n+0.5), p^(n+1.0)
      real_t dq = dq_kind[prt.kind];
      advance.push_p(prt.p, E, H, dq);

      // x^(n+0.5), p^(n+1.0) -> x^(n+1.5), p^(n+1.0)
      advance.calc_v(vv, prt.p);
      advance.push_x(x, vv);

      // CHARGE DENSITY FORM FACTOR AT (n+1.5)*dt
      current.charge_after(x);

      // CURRENT DENSITY AT (n+1.0)*dt
      current.prep(prts.prt_qni_wni(prt), vv);
      current.calc(J);
    }
  }
};

// ======================================================================
// PushParticles__

template<typename C, template<typename> class PushParticlesImpl = PushParticlesEsirkepov>
struct PushParticles__
{
  using Mparticles = typename C::Mparticles;
  using MfieldsState = typename C::MfieldsState;
  
  using checks_order = typename PushParticlesImpl<C>::checks_order;
  
  // ----------------------------------------------------------------------
  // push_mprts

  static void push_mprts(Mparticles& mprts, MfieldsState& mflds)
  {
    for (int p = 0; p < mprts.n_patches(); p++) {
      mflds[p].zero(JXI, JXI + 3);
      PushParticlesImpl<C>::push_mprts_patch(mflds[p], mprts[p]);
    }
  }

  // ----------------------------------------------------------------------
  // stagger_mprts
  
  static void stagger_mprts(Mparticles& mprts, MfieldsState& mflds)
  {
    for (int p = 0; p < mprts.n_patches(); p++) {
      PushParticlesImpl<C>::stagger_mprts_patch(mflds[p], mprts[p]);
    }
  }
};

