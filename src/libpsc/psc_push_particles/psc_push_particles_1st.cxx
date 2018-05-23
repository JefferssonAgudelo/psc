
#include "psc_push_particles_private.h"

#include "push_particles.hxx"
#include "push_config.hxx"

#include "push_part_common.c"

// ======================================================================
// psc_push_particles: subclass "1st"

template<typename DIM>
using Push = PscPushParticles_<PushParticles__<Config1stDouble<DIM>>>;

struct PushParticles1st : PushParticlesBase
{
  void push_mprts_xz(PscMparticlesBase mprts, PscMfieldsBase mflds) override
  { return Push<dim_xz>::push_mprts(mprts, mflds); }

  void push_mprts_yz(PscMparticlesBase mprts, PscMfieldsBase mflds) override
  { return Push<dim_yz>::push_mprts(mprts, mflds); }
};

using PushParticlesWrapper_t = PushParticlesWrapper<PushParticles1st>;

struct psc_push_particles_ops_1st : psc_push_particles_ops {
  psc_push_particles_ops_1st() {
    name                  = "1st";
    size                  = PushParticlesWrapper_t::size;
    setup                 = PushParticlesWrapper_t::setup;
    destroy               = PushParticlesWrapper_t::destroy;
  }
} psc_push_particles_1st_ops;

