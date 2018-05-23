
#include "psc_bnd_particles_private.h"

#include "bnd_particles_cuda_impl.hxx"

#include "dim.hxx"

// ======================================================================
// psc_bnd_particles: subclass "cuda"

struct psc_bnd_particles_ops_cuda : psc_bnd_particles_ops {
  using Wrapper = PscBndParticlesWrapper<BndParticlesCuda<BS144, dim_yz>>;
  psc_bnd_particles_ops_cuda() {
    name                    = "cuda";
    size                    = Wrapper::size;
    setup                   = Wrapper::setup;
    destroy                 = Wrapper::destroy;
  }
} psc_bnd_particles_cuda_ops;

