
#include "grid.hxx"
#include "fields.hxx"
#include "cuda_mfields.h"
#include "cuda_mparticles.h"
#include "cuda_push_particles.cuh"
#include "push_particles_cuda_impl.hxx"

#include "cuda_test.hxx"

#include "../vpic/PscRng.h"

#include <memory>

#include "gtest/gtest.h"

// Rng hackiness

using Rng = PscRng;
using RngPool = PscRngPool<Rng>;

// enum hackiness

enum { // FIXME, duplicated
#if 0
  JXI, JYI, JZI,
  EX , EY , EZ ,
  HX , HY , HZ ,
#endif
  N_FIELDS = 9,
};

// profile hackiness

#include "mrc_profile.h"

struct prof_globals prof_globals; // FIXME

int
prof_register(const char *name, float simd, int flops, int bytes)
{
  return 0;
}

using CudaMparticles = cuda_mparticles<BS144>;

// ======================================================================
// class PushMprtsTest

struct PushMprtsTest : TestBase<CudaMparticles>, ::testing::Test
{
  std::unique_ptr<Grid_t> grid_;

  RngPool rngpool;
  
  const double L = 1e10;
  const Int3 bs_ = { 1, 1, 1 };

  void SetUp()
  {
    auto domain = Grid_t::Domain{{1, 1, 1}, {L, L, L}};
    grid_.reset(new Grid_t{domain});
  }

  // FIXME, convenient interfaces like make_cmflds, make_cmprts
  // should be available generally
  template<typename S>
  std::unique_ptr<cuda_mfields> make_cmflds(S set)
  {
    auto cmflds = std::unique_ptr<cuda_mfields>(new cuda_mfields(*grid_, N_FIELDS, { 0, 2, 2 }));

    fields_single_t flds = cmflds->get_host_fields();
    Fields3d<fields_single_t> F(flds);

    F(EX, 0,0,0) = set(EX);
    F(EX, 0,1,0) = set(EX);
    F(EX, 0,0,1) = set(EX);
    F(EX, 0,1,1) = set(EX);
    
    F(EY, 0,0,0) = set(EY);
    F(EY, 0,0,1) = set(EY);
    //    F(EY, 1,0,0) = set(EY);
    //    F(EY, 1,0,1) = set(EY);
    
    F(EZ, 0,0,0) = set(EZ);
    //    F(EZ, 1,0,0) = set(EZ);
    F(EZ, 0,1,0) = set(EZ);
    //    F(EZ, 1,1,0) = set(EZ);

    F(HX, 0,0,0) = set(HX);
    F(HX, 1,0,0) = set(HX);

    F(HY, 0,0,0) = set(HY);
    F(HY, 0,1,0) = set(HY);

    F(HZ, 0,0,0) = set(HZ);
    F(HZ, 0,0,1) = set(HZ);

    cmflds->copy_to_device(0, flds, 0, N_FIELDS);
    cmflds->dump("accel.fld.json");
    flds.dtor();
  
    return cmflds;
  }

};

// ======================================================================
// Accel test

TEST_F(PushMprtsTest, Accel)
{
  const int n_prts = 131;
  const int n_steps = 10;
  const CudaMparticles::real_t eps = 1e-6;

  // init fields
  auto cmflds = make_cmflds([&] (int m) -> cuda_mfields::real_t {
      switch(m) {
      case EX: return 1.;
      case EY: return 2.;
      case EZ: return 3.;
      default: return 0.;
      }
    });

  // init particles
  Rng *rng = rngpool[0];

  grid_->kinds.push_back(Grid_t::Kind(1., 1., "test_species"));
  std::unique_ptr<CudaMparticles> cmprts(make_cmprts(*grid_, n_prts, [&](int i) -> cuda_mparticles_prt {
	cuda_mparticles_prt prt = {};
	prt.xi[0] = rng->uniform(0, L);
	prt.xi[1] = rng->uniform(0, L);
	prt.xi[2] = rng->uniform(0, L);
	prt.qni_wni = 1.;
	return prt;
      }));
  
  // run test
  for (int n = 0; n < n_steps; n++) {
    CudaPushParticles_<CudaConfig1vbec3d<dim_yz, BS144>>::push_mprts(cmprts.get(), cmflds.get());

    cmprts->get_particles(0, [&] (int i, const cuda_mparticles_prt &prt) {
	EXPECT_NEAR(prt.pxi[0], 1*(n+1), eps);
	EXPECT_NEAR(prt.pxi[1], 2*(n+1), eps);
	EXPECT_NEAR(prt.pxi[2], 3*(n+1), eps);
      });
  }
}

// ======================================================================
// Cyclo test

TEST_F(PushMprtsTest, Cyclo)
{
  const int n_prts = 131;
  const int n_steps = 64;
  // the errors here are (substantial) truncation error, not
  // finite precision, and they add up
  // (but that's okay, if a reminder that the 6th order Boris would
  //  be good)
  const CudaMparticles::real_t eps = 1e-2;

  // init fields
  auto cmflds = make_cmflds([&] (int m) -> cuda_mfields::real_t {
      switch(m) {
      case HZ: return 2. * M_PI / n_steps;
      default: return 0.;
      }
    });

  // init particles
  Rng *rng = rngpool[0];

  grid_->kinds.push_back(Grid_t::Kind(2., 1., "test_species"));
  std::unique_ptr<CudaMparticles> cmprts(make_cmprts(*grid_, n_prts, [&](int i) -> cuda_mparticles_prt {
	cuda_mparticles_prt prt = {};
	prt.xi[0] = rng->uniform(0, L);
	prt.xi[1] = rng->uniform(0, L);
	prt.xi[2] = rng->uniform(0, L);
	prt.pxi[0] = 1.; // gamma = 2
	prt.pxi[1] = 1.;
	prt.pxi[2] = 1.;
	prt.qni_wni = rng->uniform(0, 1.);;
	return prt;
      }));

  // run test
  for (int n = 0; n < n_steps; n++) {
    CudaPushParticles_<CudaConfig1vbec3d<dim_yz, BS144>>::push_mprts(cmprts.get(), cmflds.get());

    double ux = (cos(2*M_PI*(0.125*n_steps-(n+1))/(double)n_steps) /
		 cos(2*M_PI*(0.125*n_steps)      /(double)n_steps));
    double uy = (sin(2*M_PI*(0.125*n_steps-(n+1))/(double)n_steps) /
		 sin(2*M_PI*(0.125*n_steps)      /(double)n_steps));
    double uz = 1.;
    cmprts->get_particles(0, [&] (int i, const cuda_mparticles_prt &prt) {
	EXPECT_NEAR(prt.pxi[0], ux, eps);
	EXPECT_NEAR(prt.pxi[1], uy, eps);
	EXPECT_NEAR(prt.pxi[2], uz, eps);
      });
  }
}

