
#ifndef PSC_PARTICLE_SINGLE_H
#define PSC_PARTICLE_SINGLE_H

#include "psc_particles_private.h"

typedef float particle_single_real_t;

#define MPI_PARTICLES_SINGLE_REAL MPI_FLOAT

typedef struct psc_particle_single {
  particle_single_real_t xi, yi, zi;
  particle_single_real_t qni_wni;
  particle_single_real_t pxi, pyi, pzi;
  int kind;
} particle_single_t;

struct psc_particles_single {
  particle_single_t *particles;
  int n_alloced;
};

#define psc_particles_single(prts) mrc_to_subobj(prts, struct psc_particles_single)

void particles_single_realloc(struct psc_particles *prts, int new_n_part);

static inline particle_single_t *
particles_single_get_one(struct psc_particles *prts, int n)
{
  assert(psc_particles_ops(prts) == &psc_particles_single_ops);
  return &psc_particles_single(prts)->particles[n];
}

// can't do this as inline function since struct psc isn't known yet
#define particle_single_qni_div_mni(p) ({			\
      particle_single_real_t rv;				\
      rv = ppsc->kinds[p->kind].q / ppsc->kinds[p->kind].m;	\
      rv;							\
    })

#define particle_single_qni(p) ({				\
      particle_single_real_t rv;				\
      rv = ppsc->kinds[p->kind].q;				\
      rv;							\
    })

#define particle_single_wni(p) ({				\
      particle_single_real_t rv;				\
      rv = p->qni_wni / ppsc->kinds[p->kind].q;			\
      rv;							\
    })

static inline particle_single_real_t
particle_single_qni_wni(particle_single_t *p)
{
  return p->qni_wni;
}

static inline int
particle_single_kind(particle_single_t *prt)
{
  return prt->kind;
}

static inline void
particle_single_get_relative_pos(particle_single_t *p, double xb[3],
				 particle_single_real_t xi[3])
{
  xi[0] = p->xi;
  xi[1] = p->yi;
  xi[2] = p->zi;
}

static inline int
particle_single_real_nint(particle_single_real_t x)
{
  return (int)(x + 10.5f) - 10;
}

static inline int
particle_single_real_fint(particle_single_real_t x)
{
  return (int)(x + 10.f) - 10;
}

static inline particle_single_real_t
particle_single_real_sqrt(particle_single_real_t x)
{
  return sqrtf(x);
}

static inline particle_single_real_t
particle_single_real_abs(particle_single_real_t x)
{
  return fabsf(x);
}

#endif
