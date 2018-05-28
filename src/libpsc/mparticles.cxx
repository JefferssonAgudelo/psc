
#include "psc.h"

#include <mrc_profile.h>
#include <mrc_params.h>
#include <mrc_io.h>
#include <stdlib.h>
#include <string.h>

// ======================================================================

#include "particles.hxx"

#include "psc_particles_single.h"
#include "psc_particles_double.h"
#include "../libpsc/cuda/psc_particles_cuda.h"
#ifdef HAVE_VPIC
#include "psc_particles_vpic.h"
#endif

void MparticlesBase::convert(MparticlesBase& mp_from, MparticlesBase& mp_to)
{
  // FIXME, implementing == wouldn't hurt
  assert(&mp_from.grid() == &mp_to.grid());
  
  auto convert_to = mp_from.convert_to().find(std::type_index(typeid(mp_to)));
  if (convert_to != mp_from.convert_to().cend()) {
    convert_to->second(mp_from, mp_to);
    return;
  }
  
  auto convert_from = mp_to.convert_from().find(std::type_index(typeid(mp_from)));
  if (convert_from != mp_to.convert_from().cend()) {
    convert_from->second(mp_to, mp_from);
    return;
  }

  fprintf(stderr, "ERROR: no conversion known from %s to %s!\n",
	  typeid(mp_from).name(), typeid(mp_to).name());
  assert(0);
}

// ======================================================================
// psc_mparticles base class

static void
_psc_mparticles_view(struct psc_mparticles *_mprts)
{
  MPI_Comm comm = psc_mparticles_comm(_mprts);
  PscMparticlesBase mprts(_mprts);
  mpi_printf(comm, "  n_patches    = %d\n", mprts->n_patches());
  mpi_printf(comm, "  n_prts_total = %d\n", mprts->get_n_prts());

  uint n_prts_by_patch[mprts->n_patches()];
  mprts->get_size_all(n_prts_by_patch);

  for (int p = 0; p < mprts->n_patches(); p++) {
    mpi_printf(comm, "  p %d: n_prts = %d\n", p, n_prts_by_patch[p]);
  }  
}

void
psc_mparticles_check(struct psc_mparticles *_mprts_base)
{
  auto mprts_base = PscMparticlesBase{_mprts_base};
  int fail_cnt = 0;

  auto& mprts = mprts_base->get_as<MparticlesDouble>();
  const auto& grid = ppsc->grid();
  
  psc_foreach_patch(ppsc, p) {
    auto& patch = grid.patches[p];
    auto& prts = mprts[p];

    f_real xb[3], xe[3];
    
    // New-style boundary requirements.
    // These will need revisiting when it comes to non-periodic domains.
    
    for (int d = 0; d < 3; d++) {
      xb[d] = patch.xb[d];
      xe[d] = patch.xb[d] + grid.ldims[d] * grid.domain.dx[d];
    }

    for (auto prt : prts) {
      if (prt.xi < 0.f || prt.xi >= xe[0] - xb[0] || // FIXME xz only!
	  prt.zi < 0.f || prt.zi >= xe[2] - xb[2]) {
	if (fail_cnt++ < 10) {
	  mprintf("FAIL: xi %g [%g:%g]\n", prt.xi, 0., xe[0] - xb[0]);
	  mprintf("      zi %g [%g:%g]\n", prt.zi, 0., xe[2] - xb[2]);
	}
      }
    }
  }
  assert(fail_cnt == 0);

  mprts_base->put_as(mprts, MP_DONT_COPY);
}

// ======================================================================

extern struct psc_mparticles_ops psc_mparticles_single_ops;
extern struct psc_mparticles_ops psc_mparticles_double_ops;
extern struct psc_mparticles_ops psc_mparticles_sse2_ops;
extern struct psc_mparticles_ops psc_mparticles_cbe_ops;
extern struct psc_mparticles_ops psc_mparticles_cuda_ops;
extern struct psc_mparticles_ops psc_mparticles_cuda444_ops;
extern struct psc_mparticles_ops psc_mparticles_cuda2_ops;
extern struct psc_mparticles_ops psc_mparticles_acc_ops;
extern struct psc_mparticles_ops psc_mparticles_vpic_ops;
extern struct psc_mparticles_ops psc_mparticles_single_by_kind_ops;

static void
psc_mparticles_init()
{
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_single_ops);
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_double_ops);
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_single_by_kind_ops);
#ifdef USE_CUDA
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_cuda_ops);
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_cuda444_ops);
#endif
#ifdef USE_CUDA2
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_cuda2_ops);
#endif
#ifdef USE_ACC
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_acc_ops);
#endif
#ifdef USE_VPIC
  mrc_class_register_subclass(&mrc_class_psc_mparticles, &psc_mparticles_vpic_ops);
#endif
}

struct mrc_class_psc_mparticles_ : mrc_class_psc_mparticles {
  mrc_class_psc_mparticles_() {
    name             = "psc_mparticles";
    size             = sizeof(struct psc_mparticles);
    init             = psc_mparticles_init;
    view             = _psc_mparticles_view;
  }
} mrc_class_psc_mparticles;



