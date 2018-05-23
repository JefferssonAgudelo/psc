
#include "psc_checks_private.h"

#include "psc_bnd.h"
#include "psc_output_fields_item.h"
#include "fields.hxx"
#include "fields_item.hxx"
#include "checks.hxx"
#include "../libpsc/psc_output_fields/fields_item_fields.hxx"
#include "../libpsc/psc_output_fields/psc_output_fields_item_moments_1st_nc.cxx"
#include "../libpsc/psc_output_fields/psc_output_fields_item_moments_2nd_nc.cxx"

#include <mrc_io.h>

struct checks_order_1st
{
  template<typename Mparticles, typename Mfields>
  using Moment_rho_nc = Moment_rho_1st_nc<Mparticles, Mfields>;
};

struct checks_order_2nd
{
  template<typename Mparticles, typename Mfields>
  using Moment_rho_nc = Moment_rho_2nd_nc<Mparticles, Mfields>;
};

template<typename MP, typename MF, typename ORDER>
struct Checks_ : ChecksParams, ChecksBase
{
  using Mparticles = MP;
  using Mfields = MF;
  using fields_t = typename Mfields::fields_t;
  using real_t = typename Mfields::real_t;
  using Fields = Fields3d<fields_t>;
  using Moment_t = typename ORDER::template Moment_rho_nc<Mparticles, Mfields>;
  
  // ----------------------------------------------------------------------
  // ctor

  Checks_(const Grid_t& grid, MPI_Comm comm, const ChecksParams& params)
    : ChecksParams(params),
      comm_{comm},
      item_rho_{grid, comm},
      item_rho_m_{grid, comm},
      item_rho_p_{grid, comm},
      item_dive_{grid, comm},
      item_divj_{grid, comm}
  {}
  
  // ======================================================================
  // psc_checks: Charge Continuity 

  // ----------------------------------------------------------------------
  // continuity_before_particle_push

  void continuity_before_particle_push(psc *psc) override
  {
    if (continuity_every_step < 0 || psc->timestep % continuity_every_step != 0) {
      return;
    }

    auto mprts_base = PscMparticlesBase{psc->particles};
    auto mprts = mprts_base->get_as<Mparticles>();
    continuity_before_particle_push(mprts);
    mprts_base->put_as(mprts, MP_DONT_COPY);
  }

  void continuity_before_particle_push(Mparticles& mprts)
  {
    item_rho_m_.run(mprts);
  }

  // ----------------------------------------------------------------------
  // continuity_after_particle_push

  void continuity_after_particle_push(psc *psc) override
  {
    if (continuity_every_step < 0 || psc->timestep % continuity_every_step != 0) {
      return;
    }

    auto mprts_base = PscMparticlesBase{psc->particles};
    auto mflds_base = PscMfieldsBase{psc->flds};
    auto& mprts = mprts_base->get_as<Mparticles>();
    auto& mflds = mflds_base->get_as<Mfields>(0, mflds_base->n_comps());
    continuity_after_particle_push(mprts, mflds);
    mflds_base->put_as(mflds, 0, 0);
    mprts_base->put_as(mprts, MP_DONT_COPY);
  }

  void continuity_after_particle_push(Mparticles& mprts, Mfields& mflds)
  {
    item_rho_p_.run(mprts);
    item_divj_(mflds);

    auto& rho_p = item_rho_p_.result();
    auto& rho_m = item_rho_m_.result();
    auto& d_rho = rho_p;
    d_rho.axpy(-1., rho_m);

    auto& div_j = item_divj_.result();
    div_j.scale(ppsc->dt);

    double eps = continuity_threshold;
    double max_err = 0.;
    for (int p = 0; p < div_j.n_patches(); p++) {
      Fields D_rho(d_rho[p]);
      Fields Div_J(div_j[p]);
      psc_foreach_3d(ppsc, p, jx, jy, jz, 0, 0) {
	double d_rho = D_rho(0, jx,jy,jz);
	double div_j = Div_J(0, jx,jy,jz);
	max_err = fmax(max_err, fabs(d_rho + div_j));
	if (fabs(d_rho + div_j) > eps) {
	  mprintf("(%d,%d,%d): %g -- %g diff %g\n", jx, jy, jz,
		  d_rho, -div_j, d_rho + div_j);
	}
      } psc_foreach_3d_end;
    }

    // find global max
    double tmp = max_err;
    MPI_Allreduce(&tmp, &max_err, 1, MPI_DOUBLE, MPI_MAX, comm_);

    if (continuity_verbose || max_err >= eps) {
      mpi_printf(comm_, "continuity: max_err = %g (thres %g)\n", max_err, eps);
    }

    if (continuity_dump_always || max_err >= eps) {
      static struct mrc_io *io;
      if (!io) {
	io = mrc_io_create(comm_);
	mrc_io_set_name(io, "mrc_io_continuity");
	mrc_io_set_param_string(io, "basename", "continuity");
	mrc_io_set_from_options(io);
	mrc_io_setup(io);
	mrc_io_view(io);
      }
      mrc_io_open(io, "w", ppsc->timestep, ppsc->timestep * ppsc->dt);
      div_j.write_as_mrc_fld(io, "div_j", {"div_j"});
      d_rho.write_as_mrc_fld(io, "d_rho", {"d_rho"});
      mrc_io_close(io);
    }

    assert(max_err < eps);
  }
  
  // ======================================================================
  // psc_checks: Gauss's Law

  // ----------------------------------------------------------------------
  // gauss

  void gauss(psc* psc) override
  {
    if (gauss_every_step < 0 ||	psc->timestep % gauss_every_step != 0) {
      return;
    }
    
    auto mflds_base = PscMfieldsBase{psc->flds};
    auto mprts_base = PscMparticlesBase{psc->particles};
    auto& mflds = mflds_base->get_as<Mfields>(EX, EX+3);
    auto& mprts = mprts_base->get_as<Mparticles>();

    gauss(mprts, mflds);

    mflds_base->put_as(mflds, 0, 0);
    mprts_base->put_as(mprts);
}

  void gauss(Mparticles& mprts, Mfields& mflds)
  {
    const auto& grid = mprts.grid();

    item_rho_.run(mprts);
    item_dive_(mflds);

    auto& dive = item_dive_.result();
    auto& rho = item_rho_.result();
    
    double eps = gauss_threshold;
    double max_err = 0.;
    for (int p = 0; p < dive.n_patches(); p++) {
      Fields Rho(rho[p]), DivE(dive[p]);

      int l[3] = {0, 0, 0}, r[3] = {0, 0, 0};
      for (int d = 0; d < 3; d++) {
	if (grid.bc.fld_lo[d] == BND_FLD_CONDUCTING_WALL &&
	    psc_at_boundary_lo(ppsc, p, d)) {
	  l[d] = 1;
	}
      }
      
      psc_foreach_3d(ppsc, p, jx, jy, jz, 0, 0) {
	if (jy < l[1] || jz < l[2] ||
	    jy >= grid.ldims[1] - r[1] ||
	    jz >= grid.ldims[2] - r[2]) {
	  continue;
	}
	double v_rho = Rho(0, jx,jy,jz);
	double v_dive = DivE(0, jx,jy,jz);
	max_err = fmax(max_err, fabs(v_dive - v_rho));
#if 1
	if (fabs(v_dive - v_rho) > eps) {
	  printf("(%d,%d,%d): %g -- %g diff %g\n", jx, jy, jz,
		 v_dive, v_rho, v_dive - v_rho);
	}
#endif
      } psc_foreach_3d_end;
    }

    // find global max
    double tmp = max_err;
    MPI_Allreduce(&tmp, &max_err, 1, MPI_DOUBLE, MPI_MAX, comm_);

    if (gauss_verbose || max_err >= eps) {
      mpi_printf(comm_, "gauss: max_err = %g (thres %g)\n", max_err, eps);
    }

    if (gauss_dump_always || max_err >= eps) {
      static struct mrc_io *io;
      if (!io) {
	io = mrc_io_create(comm_);
	mrc_io_set_name(io, "mrc_io_gauss");
	mrc_io_set_param_string(io, "basename", "gauss");
	mrc_io_set_from_options(io);
	mrc_io_setup(io);
	mrc_io_view(io);
      }
      mrc_io_open(io, "w", ppsc->timestep, ppsc->timestep * ppsc->dt);
      rho.write_as_mrc_fld(io, "rho", {"rho"});
      dive.write_as_mrc_fld(io, "Div_E", {"Div_E"});
      mrc_io_close(io);
    }

    assert(max_err < eps);
  }

  // state
  MPI_Comm comm_;
  ItemMomentLoopPatches<Moment_t> item_rho_p_;
  ItemMomentLoopPatches<Moment_t> item_rho_m_;
  ItemMomentLoopPatches<Moment_t> item_rho_;
  FieldsItemFields<ItemLoopPatches<Item_dive<Mfields>>> item_dive_;
  FieldsItemFields<ItemLoopPatches<Item_divj<Mfields>>> item_divj_;
};

// ----------------------------------------------------------------------
// psc_checks_sub_read
//
// FIXME, this function exists to avoid a setup called twice error, but it's just a workaround

static void
psc_checks_sub_read(struct psc_checks *checks, struct mrc_io *io)
{
  psc_checks_read_super(checks, io);

  psc_checks_read_member_objs(checks, io);
}

