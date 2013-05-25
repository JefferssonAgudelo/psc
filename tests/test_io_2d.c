
#include "mrctest.h"

#include <mrc_mod.h>
#include <mrc_io.h>
#include <mrc_params.h>

#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>

// ----------------------------------------------------------------------

static void
dump_field_2d(MPI_Comm comm, struct mrc_f2 *fld, int rank_diagsrv)
{
  struct mrc_io *io;
  if (rank_diagsrv >= 0) {
    io = mrc_io_create(comm);
    mrc_io_set_type(io, "combined");
    mrc_io_set_param_int(io, "rank_diagsrv", rank_diagsrv);
  } else {
    io = mrc_io_create(comm);
  }
  mrc_io_set_from_options(io);
  mrc_io_setup(io);
  mrc_io_view(io);

  mrc_io_open(io, "w", 0, 0.);
  mrc_io_write_field2d(io, 1., fld, DIAG_TYPE_2D_Z, 99.);
  //  mrc_fld_write(fld, io);
  mrc_io_close(io);

  mrc_io_destroy(io);
}

static void
mod_domain(struct mrc_mod *mod, void *arg)
{
  struct mrctest_domain_params *par = arg;

  MPI_Comm comm = mrc_mod_get_comm(mod);
  struct mrc_domain *domain = mrctest_create_domain(comm, par);

  struct mrc_f2 fld;
  int mx = 8, my = 4;
  mrc_f2_alloc(&fld, NULL, (int [2]) { mx, my }, 1);
  fld.name[0] = strdup("test_2d_0");
  fld.domain = domain;

  for (int iy = 0; iy < my; iy++) {
    for (int ix = 0; ix < mx; ix++) {
      MRC_F2(&fld, 0, ix,iy) = 100 * iy + ix;
    }
  }

  int rank_diagsrv = mrc_mod_get_first_node(mod, "diagsrv");
  dump_field_2d(comm, &fld, rank_diagsrv);
  mrc_f2_free(&fld);

  mrc_domain_destroy(domain);
}

int
main(int argc, char **argv)
{
  mrctest_init(&argc, &argv);
  mrctest_domain(mod_domain);
  mrctest_finalize();
  return 0;
}

