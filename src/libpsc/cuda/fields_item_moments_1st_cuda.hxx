
#pragma once

#include "psc_particles_cuda.h"
#include "fields_item.hxx"
#include "bnd_cuda_impl.hxx"

// ======================================================================
// Moment_rho_1st_nc_cuda

template<typename BS>
struct Moment_rho_1st_nc_cuda : ItemMomentCRTP<Moment_rho_1st_nc_cuda<BS>, MfieldsCuda>
{
  using Base = ItemMomentCRTP<Moment_rho_1st_nc_cuda, MfieldsCuda>;
  using Mfields = MfieldsCuda;
  using Mparticles = MparticlesCuda<BS>;
  using Bnd = BndCuda;
  
  constexpr static const char* name = "rho_1st_nc";
  constexpr static int n_comps = 1;
  constexpr static fld_names_t fld_names() { return { "rho_nc_cuda" }; } // FIXME
  constexpr static int flags = 0;

  Moment_rho_1st_nc_cuda(const Grid_t& grid, MPI_Comm comm)
    : Base(grid, comm),
      bnd_{grid, ppsc->mrc_domain_, ppsc->ibn}
  {}

  void run(MparticlesCuda<BS>& mprts)
  {
    PscMfields<Mfields> mres{this->mres_};
    auto* cmprts = mprts.cmprts();
    cuda_mfields *cmres = mres->cmflds;
    
    mres->zero();
    cuda_moments_yz_rho_1st_nc(cmprts, cmres);
    bnd_.add_ghosts(mres.mflds(), 0, mres->n_comps());
  }

private:
  Bnd bnd_;
};

// ======================================================================
// n_1st_cuda

template<typename BS>
struct Moment_n_1st_cuda : ItemMomentCRTP<Moment_n_1st_cuda<BS>, MfieldsCuda>
{
  using Base = ItemMomentCRTP<Moment_n_1st_cuda, MfieldsCuda>;
  using Mfields = MfieldsCuda;
  using Mparticles = MparticlesCuda<BS>;
  using Bnd = BndCuda;
  
  constexpr static const char* name = "n_1st";
  constexpr static int n_comps = 1;
  constexpr static fld_names_t fld_names() { return { "n_1st_cuda" }; }
  constexpr static int flags = 0;

  Moment_n_1st_cuda(const Grid_t& grid, MPI_Comm comm)
    : Base(grid, comm),
      bnd_{grid, ppsc->mrc_domain_, ppsc->ibn}
  {}

  void run(MparticlesCuda<BS>& mprts)
  {
    PscMfields<Mfields> mres{this->mres_};
    auto* cmprts = mprts.cmprts();
    cuda_mfields *cmres = mres->cmflds;
    
    mres->zero();
    cuda_moments_yz_n_1st(cmprts, cmres);
    bnd_.add_ghosts(mres.mflds(), 0, mres->n_comps());
  }

private:
  Bnd bnd_;
};

