
#include "psc.h"
#include "psc_method.h"
#include "psc_push_particles.h"
#include "psc_push_fields.h"
#include "psc_bnd.h"
#include "psc_bnd_particles.h"
#include "psc_bnd_fields.h"
#include "psc_collision_private.h"
#include "psc_sort_private.h"
#include "psc_marder.h"
#include "psc_diag.h"
#include "psc_output_fields_collection.h"
#include "psc_output_particles.h"
#include "psc_event_generator.h"
#include "psc_balance.h"
#include "psc_checks.h"
#include "psc_fields_as_c.h"
#include "fields.hxx"
#include "balance.hxx"
#include "setup_fields.hxx"

#include <mrc_common.h>
#include <mrc_params.h>
#include <mrc_io.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <assert.h>
#include <time.h>
#include <array>

using Mfields_t = MfieldsC;
using Fields = Fields3d<Mfields_t::fields_t>;

struct psc *ppsc;

#define VAR(x) (void *)(offsetof(struct psc, x))
#define VAR_(x, n) (void *)(offsetof(struct psc, x) + n*sizeof(int))

static mrc_param_select bnd_fld_descr[3];
static mrc_param_select bnd_prt_descr[4];

static struct select_init {
  select_init() {
    bnd_fld_descr[0].str = "open";
    bnd_fld_descr[0].val = BND_FLD_OPEN;
    bnd_fld_descr[1].str = "periodic";
    bnd_fld_descr[1].val = BND_FLD_PERIODIC;
    bnd_fld_descr[2].str = "conducting_wall";
    bnd_fld_descr[2].val = BND_FLD_CONDUCTING_WALL;

    bnd_prt_descr[0].str = "reflecting";
    bnd_prt_descr[0].val = BND_PRT_REFLECTING;
    bnd_prt_descr[1].str = "periodic";
    bnd_prt_descr[1].val = BND_PRT_PERIODIC;
    bnd_prt_descr[2].str = "absorbing";
    bnd_prt_descr[2].val = BND_PRT_ABSORBING;
    bnd_prt_descr[3].str = "open";
    bnd_prt_descr[3].val = BND_PRT_OPEN;
  }
} select_initializer;

static struct param psc_descr[] = {
  // psc_domain
  { "length_"       , VAR(domain_.length)          , PARAM_DOUBLE3(1., 1., 1.)  },
  { "corner_"       , VAR(domain_.corner)          , PARAM_DOUBLE3(0., 0., 0.)  },
  { "gdims_"        , VAR(domain_.gdims)           , PARAM_INT3(1, 1, 1)        },
  { "np_"	    , VAR(domain_.np)	           , PARAM_INT3(1, 1, 1)        },

  { "bnd_field_lo_x", VAR_(bc_.fld_lo, 0)   , PARAM_SELECT(BND_FLD_PERIODIC,
								 bnd_fld_descr) },
  { "bnd_field_lo_y", VAR_(bc_.fld_lo, 1)   , PARAM_SELECT(BND_FLD_PERIODIC,
								 bnd_fld_descr) },
  { "bnd_field_lo_z", VAR_(bc_.fld_lo, 2)   , PARAM_SELECT(BND_FLD_PERIODIC,
								 bnd_fld_descr) },
  { "bnd_field_hi_x", VAR_(bc_.fld_hi, 0)   , PARAM_SELECT(BND_FLD_PERIODIC,
								 bnd_fld_descr) },
  { "bnd_field_hi_y", VAR_(bc_.fld_hi, 1)   , PARAM_SELECT(BND_FLD_PERIODIC,
								 bnd_fld_descr) },
  { "bnd_field_hi_z", VAR_(bc_.fld_hi, 2)   , PARAM_SELECT(BND_FLD_PERIODIC,
								 bnd_fld_descr) },

  { "bnd_particle_lo_x", VAR_(bc_.prt_lo, 0)     , PARAM_SELECT(BND_PRT_PERIODIC,
								       bnd_prt_descr) },
  { "bnd_particle_lo_y", VAR_(bc_.prt_lo, 1)     , PARAM_SELECT(BND_PRT_PERIODIC,
								       bnd_prt_descr) },
  { "bnd_particle_lo_z", VAR_(bc_.prt_lo, 2)     , PARAM_SELECT(BND_PRT_PERIODIC,
								       bnd_prt_descr) },
  { "bnd_particle_hi_x", VAR_(bc_.prt_hi, 0)     , PARAM_SELECT(BND_PRT_PERIODIC,
								       bnd_prt_descr) },
  { "bnd_particle_hi_y", VAR_(bc_.prt_hi, 1)     , PARAM_SELECT(BND_PRT_PERIODIC,
								       bnd_prt_descr) },
  { "bnd_particle_hi_z", VAR_(bc_.prt_hi, 2)     , PARAM_SELECT(BND_PRT_PERIODIC,
								       bnd_prt_descr) },

  // psc_params
  { "qq"            , VAR(prm.qq)              , PARAM_DOUBLE(1.6021e-19)   },
  { "mm"            , VAR(prm.mm)              , PARAM_DOUBLE(9.1091e-31)   },
  { "tt"            , VAR(prm.tt)              , PARAM_DOUBLE(1.6021e-16)   },
  { "cc"            , VAR(prm.cc)              , PARAM_DOUBLE(3.0e8)        },
  { "eps0"          , VAR(prm.eps0)            , PARAM_DOUBLE(8.8542e-12)   },
  { "nmax"          , VAR(prm.nmax)            , PARAM_INT(0)               },
  { "lw"            , VAR(prm.lw)              , PARAM_DOUBLE(3.2e-6)       },
  { "i0"            , VAR(prm.i0)              , PARAM_DOUBLE(1e21)         },
  { "n0"            , VAR(prm.n0)              , PARAM_DOUBLE(1e26)         },
  { "e0"            , VAR(prm.e0)              , PARAM_DOUBLE(0.)           },
  { "cfl"           , VAR(prm.cfl)             , PARAM_DOUBLE(.75)          },
  { "nicell"        , VAR(prm.nicell)          , PARAM_INT(200)             },
  { "neutralizing_population", VAR(prm.neutralizing_population)  , PARAM_INT(-1),
    .help = "this population will get density set to achieve neutrality "
    "in a given cell." },
  // by default, we put the # of particles per cell according to the
  // density, using the weights (~ 1) only to fine-tune to the
  // right density.
  // if this parameter is set, we always use nicell particles / cell,
  // and adjust to the right density via the weights.
  { "fractional_n_particles_per_cell"
                    , VAR(prm.fractional_n_particles_per_cell), PARAM_BOOL(0)  },
  { "const_num_particles_per_cell"
                    , VAR(prm.const_num_particles_per_cell), PARAM_BOOL(0)  },
  { "initial_momentum_gamma_correction"
                    , VAR(prm.initial_momentum_gamma_correction), PARAM_BOOL(0),
    .help = "if set, interpret momenta as velocities and multiply by gamma to get "
    "relativistic momenta." },
  
  { "wallclock_limit"
                    , VAR(prm.wallclock_limit)    , PARAM_DOUBLE(0.) },
  { "write_checkpoint"
                    , VAR(prm.write_checkpoint)   , PARAM_BOOL(false) },
  { "write_checkpoint_every_step"
                    , VAR(prm.write_checkpoint_every_step), PARAM_INT(-1) },

  { "fields_base"   , VAR(prm.fields_base)        , PARAM_STRING("c") },
  { "particles_base", VAR(prm.particles_base)     , PARAM_STRING("double") },
  { "stats_every"
                    , VAR(prm.stats_every)        , PARAM_INT(1),
    .help = "sets every how many steps we log timing and other stats." },
  { "detailed_profiling"
                    , VAR(prm.detailed_profiling) , PARAM_BOOL(false),
    .help = "output profiling information by MPI process rather than aggregated." },
  { "theta_xz"      , VAR(prm.theta_xz)           , PARAM_DOUBLE(0.),
    .help = "rotate initial particle shifted Maxwellian in x-z plane." },

  { "n_state_fields", VAR(n_state_fields)         , MRC_VAR_INT },

  { "method"                  , VAR(method)                  , MRC_VAR_OBJ(psc_method) },
  { "push_particles"          , VAR(push_particles)          , MRC_VAR_OBJ(psc_push_particles) },
  { "push_fields"             , VAR(push_fields)             , MRC_VAR_OBJ(psc_push_fields) },
  { "bnd"                     , VAR(bnd)                     , MRC_VAR_OBJ(psc_bnd) },
  { "bnd_particles"           , VAR(bnd_particles)           , MRC_VAR_OBJ(psc_bnd_particles) },
  { "collision"               , VAR(collision)               , MRC_VAR_OBJ(psc_collision) },
  { "marder"                  , VAR(marder)                  , MRC_VAR_OBJ(psc_marder) },
  { "sort"                    , VAR(sort)                    , MRC_VAR_OBJ(psc_sort) },
  { "diag"                    , VAR(diag)                    , MRC_VAR_OBJ(psc_diag) },
  { "output_fields_collection", VAR(output_fields_collection), MRC_VAR_OBJ(psc_output_fields_collection) },
  { "output_particles"        , VAR(output_particles)        , MRC_VAR_OBJ(psc_output_particles) },
  { "event_generator"         , VAR(event_generator)         , MRC_VAR_OBJ(psc_event_generator) },
  { "checks"                  , VAR(checks)                  , MRC_VAR_OBJ(psc_checks) },

  {},
};

#undef VAR

// ----------------------------------------------------------------------
// psc_create

static void
_psc_create(struct psc *psc)
{
  assert(!ppsc);
  ppsc = psc;

  int rank;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  srandom(rank);
  
  // default: 2 species (e-, i+)
  psc_set_kinds(psc, {{ -1., 1., "e"}, { 1., 100., "i" }});

  // default 9 state fields (J,E,B)
  psc->n_state_fields = NR_FIELDS;

  psc_bnd_set_psc(psc->bnd, psc); // FIXME, do general parent interface?
  psc_bnd_particles_set_psc(psc->bnd_particles, psc);
  psc_output_fields_collection_set_psc(psc->output_fields_collection, psc);

  psc->time_start = MPI_Wtime();

  psc->balance = psc_balance_create(psc_comm(psc));
}

// ----------------------------------------------------------------------
// psc_set_from_options

static void
_psc_set_from_options(struct psc *psc)
{
  psc_balance_set_from_options(psc->balance);
}

// ======================================================================
// psc_setup

// ----------------------------------------------------------------------
// psc_setup_coeff

void
psc_setup_coeff(struct psc *psc)
{
  assert(psc->prm.nicell > 0);
  psc->coeff_.cori = 1. / psc->prm.nicell;
  psc->coeff_.wl = 2. * M_PI * psc->prm.cc / psc->prm.lw;
  psc->coeff_.ld = psc->prm.cc / psc->coeff_.wl;
  if (psc->prm.e0 == 0.) {
    psc->prm.e0 = sqrt(2.0 * psc->prm.i0 / psc->prm.eps0 / psc->prm.cc) /
      psc->prm.lw / 1.0e6;
  }
  psc->prm.b0 = psc->prm.e0 / psc->prm.cc;
  psc->prm.rho0 = psc->prm.eps0 * psc->coeff_.wl * psc->prm.b0;
  psc->prm.phi0 = psc->coeff_.ld * psc->prm.e0;
  psc->prm.a0 = psc->prm.e0 / psc->coeff_.wl;
  psc->coeff_.vos = psc->prm.qq * psc->prm.e0 / (psc->prm.mm * psc->coeff_.wl);
  psc->coeff_.vt = sqrt(psc->prm.tt / psc->prm.mm);
  psc->coeff_.wp = sqrt(sqr(psc->prm.qq) * psc->prm.n0 / psc->prm.eps0 / psc->prm.mm);
  psc->coeff_.alpha = psc->coeff_.wp / psc->coeff_.wl;
  psc->coeff_.beta = psc->coeff_.vt / psc->prm.cc;
  psc->coeff_.eta = psc->coeff_.vos / psc->prm.cc;
}

// ----------------------------------------------------------------------
// psc_setup_mrc_domain

struct mrc_domain *
psc_setup_mrc_domain(const Grid_t::Domain& grid_domain, const GridBc& grid_bc, int nr_patches)
{
  // FIXME, should be split to create, set_from_options, setup time?
  struct mrc_domain *domain = mrc_domain_create(MPI_COMM_WORLD);
  // create a very simple domain decomposition
  int bc[3] = {};
  for (int d = 0; d < 3; d++) {
    if (grid_bc.fld_lo[d] == BND_FLD_PERIODIC && grid_domain.gdims[d] > 1) {
      bc[d] = BC_PERIODIC;
    }
  }

  mrc_domain_set_type(domain, "multi");
  mrc_domain_set_param_int3(domain, "m", grid_domain.gdims);
  mrc_domain_set_param_int(domain, "bcx", bc[0]);
  mrc_domain_set_param_int(domain, "bcy", bc[1]);
  mrc_domain_set_param_int(domain, "bcz", bc[2]);
  mrc_domain_set_param_int(domain, "nr_patches", nr_patches);
  mrc_domain_set_param_int3(domain, "np", grid_domain.np);

  struct mrc_crds *crds = mrc_domain_get_crds(domain);
  mrc_crds_set_type(crds, "uniform");
  mrc_crds_set_param_int(crds, "sw", 2);
  mrc_crds_set_param_double3(crds, "l", grid_domain.corner);
  mrc_crds_set_param_double3(crds, "h", grid_domain.corner + grid_domain.length);

  mrc_domain_set_from_options(domain);
  mrc_domain_setup(domain);

  return domain;
}

// ----------------------------------------------------------------------
// psc_make_grid

Grid_t* psc::make_grid(struct mrc_domain* mrc_domain, const Grid_t::Domain& domain, const GridBc& bc,
		       const Grid_t::Kinds& kinds)
{
  Int3 gdims;
  mrc_domain_get_global_dims(mrc_domain, gdims);
  int n_patches;
  mrc_patch *patches = mrc_domain_get_patches(mrc_domain, &n_patches);
  assert(n_patches > 0);
  Int3 ldims = patches[0].ldims;
  std::vector<Int3> offs;
  for (int p = 0; p < n_patches; p++) {
    assert(ldims == Int3(patches[p].ldims));
    offs.push_back(patches[p].off);
  }

  Grid_t *grid = new Grid_t(domain, offs);

  grid->kinds = kinds;

  grid->bc = bc;
  for (int d = 0; d < 3; d++) {
    if (grid->isInvar(d)) {
      // if invariant in this direction: set bnd to periodic (FIXME?)
      grid->bc.fld_lo[d] = BND_FLD_PERIODIC;
      grid->bc.fld_hi[d] = BND_FLD_PERIODIC;
      grid->bc.prt_lo[d] = BND_PRT_PERIODIC;
      grid->bc.prt_hi[d] = BND_PRT_PERIODIC;
    }
  }
  
  assert(coeff_.ld == 1.);
  grid->fnqs = sqr(coeff_.alpha) * coeff_.cori / coeff_.eta;
  grid->eta = coeff_.eta;
  grid->beta = coeff_.beta;
  grid->cori = coeff_.cori;
  grid->dt = dt;

  return grid;
}

// ----------------------------------------------------------------------
// psc_set_dt

double psc_set_dt(psc* psc, const Grid_t::Domain& domain)
{
  double inv_sum = 0.;
  for (int d = 0; d < 3; d++) {
    if (!domain.isInvar(d)) {
      inv_sum += 1. / sqr(domain.dx[d]);
    }
  }
  if (!inv_sum) { // simulation has 0 dimensions
    inv_sum = 1.;
  }
  return psc->prm.cfl * sqrt(1./inv_sum);
}

// ----------------------------------------------------------------------
// psc_setup_domain

void psc_setup_domain(struct psc *psc, const Grid_t::Domain& domain, GridBc& bc, const Grid_t::Kinds& kinds)
{
  if (!psc->dt) {
    psc->dt = psc_set_dt(psc, domain);
  }
#if 0
  mpi_printf(MPI_COMM_WORLD, "::: dt      = %g\n", psc->dt);
  mpi_printf(MPI_COMM_WORLD, "::: dx      = %g %g %g\n", domain.dx[0], domain.dx[1], domain.dx[2]);
#endif
  
  for (int d = 0; d < 3; d++) {
    if (psc->ibn[d] != 0) {
      continue;
    }
    // FIXME, old-style particle pushers need 3 ghost points still
    if (domain.gdims[d] == 1) {
      // no ghost points
      psc->ibn[d] = 0;
    } else {
      psc->ibn[d] = 2;
    }
  }

  psc->mrc_domain_ = psc_setup_mrc_domain(domain, bc, -1);
  psc->grid_ = psc->make_grid(psc->mrc_domain_, domain, bc, kinds);
}

// ----------------------------------------------------------------------
// _psc_setup

static void
_psc_setup(struct psc *psc)
{
  psc_method_do_setup(psc->method, psc);

  // partition and initial balancing
  auto n_prts_by_patch_old = psc_method_setup_partition(psc->method, psc);
  psc_balance_setup(psc->balance);
  auto balance = PscBalanceBase{psc->balance};
  auto n_prts_by_patch_new = balance.initial(psc, n_prts_by_patch_old);

  // create and initialize base particle data structure x^{n+1/2}, p^{n+1/2}
  psc->particles = PscMparticlesCreate(psc_comm(psc), psc->grid(),
				       psc->prm.particles_base).mprts();
  psc_method_set_ic_particles(psc->method, psc, n_prts_by_patch_new);

  // create and set up base mflds
  psc->flds = PscMfieldsCreate(psc_comm(psc), psc->grid(),
			       psc->n_state_fields, psc->ibn, psc->prm.fields_base).mflds();
  psc_method_set_ic_fields(psc->method, psc);

#ifdef USE_FORTRAN
  psc_setup_fortran(psc);
#endif

  psc_setup_member_objs(psc);
}

// ----------------------------------------------------------------------
// psc_destroy

static void
_psc_destroy(struct psc *psc)
{
  psc_mfields_destroy(psc->flds);
  psc_mparticles_destroy(psc->particles);

  mrc_domain_destroy(psc->mrc_domain_);

  ppsc = NULL;
}

// ----------------------------------------------------------------------
// _psc_write

static void
_psc_write(struct psc *psc, struct mrc_io *io)
{
  mrc_io_write_int(io, psc, "timestep", psc->timestep);
#if 0
  mrc_io_write_int(io, psc, "nr_kinds", psc->nr_kinds_);

  for (int k = 0; k < psc->nr_kinds_; k++) {
    char s[20];
    sprintf(s, "kind_q%d", k);
    mrc_io_write_double(io, psc, s, psc->kinds_[k].q);
    sprintf(s, "kind_m%d", k);
    mrc_io_write_double(io, psc, s, psc->kinds_[k].m);
    mrc_io_write_string(io, psc, s, psc->kinds_[k].name);
  }
#endif
  mrc_io_write_ref(io, psc, "mrc_domain", psc->mrc_domain_);
  mrc_io_write_ref(io, psc, "mparticles", psc->particles);
  mrc_io_write_ref(io, psc, "mfields", psc->flds);
}

// ----------------------------------------------------------------------
// _psc_read

static void
_psc_read(struct psc *psc, struct mrc_io *io)
{
  assert(!ppsc);
  ppsc = psc;

  psc_setup_coeff(psc);

  mrc_io_read_int(io, psc, "timestep", &psc->timestep);
#if 0
  mrc_io_read_int(io, psc, "nr_kinds", &psc->nr_kinds_);
  psc->kinds_ = new psc_kind[psc->nr_kinds_]();
  for (int k = 0; k < psc->nr_kinds_; k++) {
    char s[20];
    sprintf(s, "kind_q%d", k);
    mrc_io_read_double(io, psc, s, &psc->kinds_[k].q);
    sprintf(s, "kind_m%d", k);
    mrc_io_read_double(io, psc, s, &psc->kinds_[k].m);
    mrc_io_read_string(io, psc, s, &psc->kinds_[k].name);
  }
#endif
  
  psc->mrc_domain_ = mrc_io_read_ref(io, psc, "mrc_domain", mrc_domain);
  psc_setup_domain(psc, psc->domain_, psc->bc_, psc->kinds_);
#ifdef USE_FORTRAN
  psc_setup_fortran(psc);
#endif

  psc->particles = mrc_io_read_ref(io, psc, "mparticles", psc_mparticles);
  psc->flds = mrc_io_read_ref(io, psc, "mfields", psc_mfields);

  psc_read_member_objs(psc, io);

  psc->time_start = MPI_Wtime();
}

// ----------------------------------------------------------------------
// psc_set_ic_fields
//
// set i.c. on E^{n+1/2}, B^{n+1/2}

void
psc_set_ic_fields(struct psc *psc)
{
  // type-specific other initial condition
  if (psc_ops(psc)->setup_fields) {
    psc_ops(psc)->setup_fields(psc, psc->flds);
  } else {
    SetupFields<Mfields_t>::set_ic(psc);
  }
}

// ----------------------------------------------------------------------
// _psc_view

static void
_psc_view(struct psc *psc)
{
  const auto& kinds = psc->grid().kinds;
  mrc_domain_view(psc->mrc_domain_);

  MPI_Comm comm = psc_comm(psc);
  mpi_printf(comm, "%20s|\n", "particle kinds");
  for (int k = 0; k < kinds.size(); k++) {
    mpi_printf(comm, "%19s | q = %g m = %g\n",
	       kinds[k].name, kinds[k].q, kinds[k].m);
  }
}

// ----------------------------------------------------------------------
// psc_set_kinds

void psc_set_kinds(struct psc *psc, const Grid_t::Kinds& kinds)
{
  psc->kinds_ = kinds;
}

// ======================================================================
// psc class

struct mrc_class_psc_ : mrc_class_psc {
  mrc_class_psc_() {
    name             = "psc";
    size             = sizeof(struct psc);
    param_descr      = psc_descr;
    create           = _psc_create;
    set_from_options = _psc_set_from_options;
    setup            = _psc_setup;
    view             = _psc_view;
    destroy          = _psc_destroy;
    write            = _psc_write;
    read             = _psc_read;
  }
} mrc_class_psc;

// ======================================================================
// helpers

// ----------------------------------------------------------------------
// psc_default_dimensionless
//
// sets up parameter defaults for dimensionless units

void
psc_default_dimensionless(struct psc *psc)
{
  psc->prm.qq = 1.;
  psc->prm.mm = 1.;
  psc->prm.tt = 1.;
  psc->prm.cc = 1.;
  psc->prm.eps0 = 1.;

  psc->prm.lw = 2.*M_PI;
  psc->prm.i0 = 0.;
  psc->prm.n0 = 1.;
  psc->prm.e0 = 1.;
}

