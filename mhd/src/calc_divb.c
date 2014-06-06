
#include "ggcm_mhd_defs.h"
#include "ggcm_mhd_private.h"
#include "ggcm_mhd_crds.h"

#include <mrc_fld.h>
#include <mrc_domain.h>

#include <stdio.h>
#include <math.h>
#include <assert.h>

#include <mrc_fld_as_double.h>

// ----------------------------------------------------------------------
// ggcm_mhd_calc_divb

void
ggcm_mhd_calc_divb(struct ggcm_mhd *mhd, struct mrc_fld *fld, struct mrc_fld *divb)
{
  struct mrc_patch_info info;
  mrc_domain_get_local_patch_info(fld->_domain, 0, &info);

  float *bd2x = ggcm_mhd_crds_get_crd(mhd->crds, 0, BD2);
  float *bd2y = ggcm_mhd_crds_get_crd(mhd->crds, 1, BD2);
  float *bd2z = ggcm_mhd_crds_get_crd(mhd->crds, 2, BD2);

  mrc_fld_data_t hx = 1., hy = 1., hz = 1.;
  int gdims[3];
  mrc_domain_get_global_dims(fld->_domain, gdims);
  if (gdims[0] == 1) hx = 0.;
  if (gdims[1] == 1) hy = 0.;
  if (gdims[2] == 1) hz = 0.;

  struct mrc_fld *f = mrc_fld_get_as(fld, FLD_TYPE);
  struct mrc_fld *d = mrc_fld_get_as(divb, FLD_TYPE);

  mrc_fld_data_t max = 0.;

  int mhd_type;
  mrc_fld_get_param_int(fld, "mhd_type", &mhd_type);

  if (mhd_type == MT_SEMI_CONSERVATIVE_GGCM) {
    mrc_fld_foreach(divb, ix,iy,iz, 0, 0) {
      F3(d,0, ix,iy,iz) = 
	(B1X(f, ix,iy,iz) - B1X(f, ix-1,iy,iz)) / bd2x[ix] +
	(B1Y(f, ix,iy,iz) - B1Y(f, ix,iy-1,iz)) / bd2y[iy] +
	(B1Z(f, ix,iy,iz) - B1Z(f, ix,iy,iz-1)) / bd2z[iz];
      F3(d,0, ix,iy,iz) *= F3(f,_YMASK, ix,iy,iz);

      // the incoming solar wind won't match and hence divb != 0 here
      if (info.off[0] == 0 && ix <= 0)
	continue;
      max = mrc_fld_max(max, mrc_fld_abs(F3(d,0, ix,iy,iz)));
    } mrc_fld_foreach_end;
  } else if (mhd_type == MT_SEMI_CONSERVATIVE ||
	     mhd_type == MT_FULLY_CONSERVATIVE) {
    mrc_fld_foreach(divb, ix,iy,iz, 0, 0) {
      F3(d,0, ix,iy,iz) = 
	(B1X(f, ix+1,iy,iz) - B1X(f, ix,iy,iz)) * hx / bd2x[ix] +
	(B1Y(f, ix,iy+1,iz) - B1Y(f, ix,iy,iz)) * hy / bd2y[iy] +
	(B1Z(f, ix,iy,iz+1) - B1Z(f, ix,iy,iz)) * hz / bd2z[iz];
      F3(d,0, ix,iy,iz) *= F3(f,_YMASK, ix,iy,iz);

      max = mrc_fld_max(max, mrc_fld_abs(F3(d,0, ix,iy,iz)));
    } mrc_fld_foreach_end;
  } else {
    assert(0);
  }

  mrc_fld_put_as(f, fld);
  mrc_fld_put_as(d, divb);

  mprintf("max divb = %g\n", max);
}

