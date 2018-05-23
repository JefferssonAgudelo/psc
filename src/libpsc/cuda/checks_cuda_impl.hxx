
#pragma once

#include "checks.hxx"

template<typename BS>
struct ChecksCuda : ChecksBase, ChecksParams
{
  ChecksCuda(const Grid_t& grid, MPI_Comm comm, const ChecksParams& params)
    : ChecksParams(params)
  {}
  
  void continuity_before_particle_push(psc* psc) { assert(0); }
  void continuity_after_particle_push(psc* psc) { assert(0); }
  void gauss(psc* psc) { assert(0); }

  void continuity_before_particle_push(MparticlesCuda<BS>& mprts)
  {}
 
  void continuity_after_particle_push(MparticlesCuda<BS>& mprts, MfieldsCuda& mflds)
  {}

  void gauss(MparticlesCuda<BS>& mprts, MfieldsCuda& mflds)
  {}
};
