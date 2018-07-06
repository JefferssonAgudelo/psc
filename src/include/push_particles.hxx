
#pragma once

#include "psc_push_particles_private.h"
#include "particles.hxx"
#include "fields3d.hxx"

extern int pr_time_step_no_comm; // FIXME

// ======================================================================
// PushParticlesBase

class PushParticlesBase
{
public:
  virtual void prep(MparticlesBase& mprts_base, PscMfieldsBase mflds_base)
  { assert(0); }
  
  virtual void push_mprts(MparticlesBase& mprts_base, PscMfieldsBase mflds_base)
  {
    const auto& grid = mprts_base.grid();
    using Bool3 = Vec3<bool>;
    Bool3 invar{grid.isInvar(0), grid.isInvar(1), grid.isInvar(2)};

    // if this function has not been overriden, call the pusher for the appropriate dims
    if (invar == Bool3{false, true, true}) { // x
      push_mprts_x(mprts_base, mflds_base);
    } else if (invar == Bool3{true, false, true}) { // y
      push_mprts_y(mprts_base, mflds_base);
    } else if (invar == Bool3{true, true, false}) { // z
      push_mprts_z(mprts_base, mflds_base);
    } else if (invar == Bool3{false, false, true}) { // xy
      push_mprts_xy(mprts_base, mflds_base);
    } else if (invar == Bool3{false, true, false}) { // xz
      push_mprts_xz(mprts_base, mflds_base);
    } else if (invar == Bool3{true, false, false}) { // yz
      push_mprts_yz(mprts_base, mflds_base);
    } else if (invar == Bool3{false, false, false}) { // xyz
      push_mprts_xyz(mprts_base, mflds_base);
    } else {
      push_mprts_1(mprts_base, mflds_base);
    }
  }

  virtual void push_mprts_xyz(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void push_mprts_xy(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void push_mprts_xz(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void push_mprts_yz(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void push_mprts_x(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void push_mprts_y(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void push_mprts_z(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void push_mprts_1(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { assert(0); }

  virtual void stagger_mprts(MparticlesBase& mprts_base, PscMfieldsBase mflds_base)
  {
    const auto& grid = mprts_base.grid();
    using Bool3 = Vec3<bool>;
    Bool3 invar{grid.isInvar(0), grid.isInvar(1), grid.isInvar(2)};

    if (invar == Bool3{true, false, false}) { // yz
      stagger_mprts_yz(mprts_base, mflds_base);
    } else if (invar == Bool3{true, true, true}) { // 1
      stagger_mprts_1(mprts_base, mflds_base);
    } else {
      mprintf("WARNING: no stagger_mprts() case!\n");
    }
  }
  
  virtual void stagger_mprts_yz(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { mprintf("WARNING: %s not implemented\n", __func__); }

  virtual void stagger_mprts_1(MparticlesBase& mprts, PscMfieldsBase mflds_base)
  { mprintf("WARNING: %s not implemented\n", __func__); }

};

// ======================================================================
// PscPushParticles

template<typename S>
struct PscPushParticles
{
  using sub_t = S;

  explicit PscPushParticles(psc_push_particles *pushp)
    : pushp_(pushp),
      sub_(mrc_to_subobj(pushp, sub_t))
  {}

  void operator()(MparticlesBase& mprts_base, PscMfieldsBase mflds_base)
  {
    static int pr;
    if (!pr) {
      pr = prof_register("push_particles_run", 1., 0, 0);
    }  
    
    prof_start(pr);
    prof_restart(pr_time_step_no_comm);
    psc_stats_start(st_time_particle);
    
    sub()->push_mprts(mprts_base, mflds_base.mflds());
    
    psc_stats_stop(st_time_particle);
    prof_stop(pr_time_step_no_comm);
    prof_stop(pr);
  }

  void stagger(MparticlesBase& mprts_base, PscMfieldsBase mflds_base)
  {
    sub()->stagger_mprts(mprts_base, mflds_base.mflds());
  }
  
  psc_push_particles *pushp() { return pushp_; }
  
  sub_t* operator->() { return sub_; }

  sub_t* sub() { return sub_; }

private:
  psc_push_particles *pushp_;
  sub_t *sub_;
};

using PscPushParticlesBase = PscPushParticles<PushParticlesBase>;

// ======================================================================
// PscPushParticles_
//
// wraps PushParticles in get_as / put_as

template<class PushParticles_t>
struct PscPushParticles_
{
  using Mparticles = typename PushParticles_t::Mparticles;
  using Mfields = typename PushParticles_t::Mfields;
  
  static void push_mprts(MparticlesBase& mprts_base, PscMfieldsBase mflds_base)
  {
    auto& mflds = mflds_base->get_as<Mfields>(EX, EX + 6);
    auto& mprts = mprts_base.get_as<Mparticles>();
    PushParticles_t::push_mprts(mprts, mflds);
    mprts_base.put_as(mprts);
    mflds_base->put_as(mflds, JXI, JXI+3);
  }
  
  static void stagger_mprts(MparticlesBase& mprts_base, PscMfieldsBase mflds_base)
  {
    auto& mflds = mflds_base->get_as<Mfields>(EX, EX + 6);
    auto& mprts = mprts_base.get_as<Mparticles>();
    PushParticles_t::stagger_mprts(mprts, mflds);
    mprts_base.put_as(mprts);
    mflds_base->put_as(mflds, JXI, JXI+3);
  }

  PushParticles_t pushp_;
};

template<typename PushParticles_t>
class PushParticlesWrapper
{
public:
  const static size_t size = sizeof(PushParticles_t);
  
  static void setup(struct psc_push_particles *push)
  {
    PscPushParticles<PushParticles_t> pushp(push);
    new(pushp.sub()) PushParticles_t;
  }

  static void destroy(struct psc_push_particles *push)
  {
    PscPushParticles<PushParticles_t> pushp(push);
    pushp.sub()->~PushParticles_t();
  }
};

