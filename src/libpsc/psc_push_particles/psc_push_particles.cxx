
#include "psc_push_particles_private.h"

#include "psc_push_fields_private.h"
#include "psc_bnd_fields.h"
#include "psc_bnd.h"
#include "push_particles.hxx"

#include <mrc_profile.h>

// ======================================================================
// forward to subclass

extern int pr_time_step_no_comm;
extern double *psc_balance_comp_time_by_patch;

void
psc_push_particles_prep(struct psc_push_particles *push,
			struct psc_mparticles *mprts_base, struct psc_mfields *mflds_base)
{
  static int pr;
  if (!pr) {
    pr = prof_register("push_particles_prep", 1., 0, 0);
  }  

  struct psc_push_particles_ops *ops = psc_push_particles_ops(push);

  prof_start(pr);
  prof_restart(pr_time_step_no_comm);
  psc_stats_start(st_time_particle);

  if (ops->prep) {
    ops->prep(push, mprts_base, mflds_base);
  }

  psc_stats_stop(st_time_particle);
  prof_stop(pr_time_step_no_comm);
  prof_stop(pr);
}

// ======================================================================
// psc_push_particles_init

extern struct psc_push_particles_ops psc_push_particles_generic_c_ops;
extern struct psc_push_particles_ops psc_push_particles_1st_ops;
extern struct psc_push_particles_ops psc_push_particles_1vb_single_ops;
extern struct psc_push_particles_ops psc_push_particles_1vb_double_ops;
extern struct psc_push_particles_ops psc_push_particles_1vb_ps_ops;
extern struct psc_push_particles_ops psc_push_particles_1vb_ps2_ops;
extern struct psc_push_particles_ops psc_push_particles_1vbec_single_ops;
extern struct psc_push_particles_ops psc_push_particles_1vbec_double_ops;
extern struct psc_push_particles_ops psc_push_particles_fortran_ops;
extern struct psc_push_particles_ops psc_push_particles_vay_ops;
extern struct psc_push_particles_ops psc_push_particles_sse2_ops;
extern struct psc_push_particles_ops psc_push_particles_cbe_ops;
extern struct psc_push_particles_ops psc_push_particles_1vb_cuda_ops;
extern struct psc_push_particles_ops psc_push_particles_1vbec3d_cuda_ops;
extern struct psc_push_particles_ops psc_push_particles_1vbec3d_gmem_cuda_ops;
extern struct psc_push_particles_ops psc_push_particles_1vbec_cuda2_ops;
extern struct psc_push_particles_ops psc_push_particles_1vbec_cuda2_host_ops;
extern struct psc_push_particles_ops psc_push_particles_1vbec_acc_ops;
extern struct psc_push_particles_ops psc_push_particles_vpic_ops;

static void
psc_push_particles_init()
{
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_generic_c_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1st_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vb_single_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vb_double_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vbec_single_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vbec_double_ops);
#ifdef USE_FORTRAN
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_fortran_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_vay_ops);
#endif
#ifdef USE_SSE2
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vb_ps_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vb_ps2_ops);
#endif
#ifdef USE_CBE
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_cbe_ops);
#endif
#ifdef USE_CUDA
  //  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vb_cuda_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vbec3d_cuda_ops);
  //  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vbec3d_gmem_cuda_ops);
#endif
#ifdef USE_CUDA2
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vbec_cuda2_host_ops);
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vbec_cuda2_ops);
#endif
#ifdef USE_ACC
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_1vbec_acc_ops);
#endif
#ifdef USE_VPIC
  mrc_class_register_subclass(&mrc_class_psc_push_particles, &psc_push_particles_vpic_ops);
#endif
}

// ======================================================================
// psc_push_particles class

struct mrc_class_psc_push_particles_ : mrc_class_psc_push_particles {
  mrc_class_psc_push_particles_() {
    name             = "psc_push_particles";
    size             = sizeof(struct psc_push_particles);
    init             = psc_push_particles_init;
  }
} mrc_class_psc_push_particles;

