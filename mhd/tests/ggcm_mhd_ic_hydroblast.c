
#include "ggcm_mhd_ic_private.h"

#include "ggcm_mhd_defs.h"
#include "ggcm_mhd_private.h"

#include <mrc_domain.h>
#include <mrc_crds.h>
#include <math.h>
#include <string.h>
#include <assert.h>

#define ggcm_mhd_cweno(obj) mrc_to_subobj(obj, struct mhd)

// ======================================================================
// ggcm_mhd_ic subclass "hydroblast"

struct ggcm_mhd_ic_hydroblast {
  float initrad; // inital radius
  float pin; // initial inside  pressure
  float pout; // initial outside pressure
  float n0; // initial density 
  const char* pdim; 
};
// ----------------------------------------------------------------------
// ggcm_mhd_ic_hydroblast_run

static void
ggcm_mhd_ic_hydroblast_run(struct ggcm_mhd_ic *ic)
{
  struct ggcm_mhd_ic_hydroblast *sub = mrc_to_subobj(ic, struct ggcm_mhd_ic_hydroblast);
  struct ggcm_mhd *gmhd = ic->mhd;  
  struct mrc_fld *fld = gmhd->fld;
  struct mrc_crds *crds = mrc_domain_get_crds(gmhd->domain);  
  float xl[3], xh[3], r[3];//, L[3]
  mrc_crds_get_param_float3(crds, "l", xl);
  mrc_crds_get_param_float3(crds, "h", xh);
  /* for(int i=0; i<3; i++){ */
  /*   L[i] = xh[i] - xl[i]; */
  /* } */
  float gamma = gmhd->par.gamm;
  mrc_fld_foreach(fld, ix, iy, iz, 1, 1) {
    r[0] = MRC_CRD(crds, 0, ix);
    r[1] = MRC_CRD(crds, 1, iy);
    r[2] = MRC_CRD(crds, 2, iz);
  
    if((strcmp(sub->pdim, "xy") || (strcmp(sub->pdim,"yx")))== 1){
	MRC_F3(fld, _RR1, ix, iy, iz) = sub->n0;
	if( sqrt((r[0]*r[0]) + (r[1]*r[1])) <= sub->initrad ){
	  MRC_F3(fld, _UU1 , ix, iy, iz) = sub->pin / (gamma - 1.f);
	} else{	
	  MRC_F3(fld, _UU1 , ix, iy, iz) = sub->pout / (gamma - 1.f);
	}
    } else if((strcmp(sub->pdim, "yz") || (strcmp(sub->pdim,"zy"))) == 1){
	  MRC_F3(fld, _RR1, ix, iy, iz) = sub->n0;
	  if( sqrt((r[1]*r[1]) + (r[2]*r[2])) <= sub->initrad ){	
	    MRC_F3(fld, _UU1 , ix, iy, iz) = sub->pin / (gamma - 1.f) +
	      .5f * (sqr(MRC_F3(fld, _RV1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Z, ix, iy, iz))) / MRC_F3(fld, _RR1, ix, iy, iz) +
	      .5f * (sqr(MRC_F3(fld, _B1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Z, ix, iy, iz)));      
	  } else{	
	    MRC_F3(fld, _UU1 , ix, iy, iz) = sub->pout / (gamma - 1.f) +
	      .5f * (sqr(MRC_F3(fld, _RV1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Z, ix, iy, iz))) / MRC_F3(fld, _RR1, ix, iy, iz) +
	      .5f * (sqr(MRC_F3(fld, _B1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Z, ix, iy, iz)));      
	  }
	  MRC_F3(fld, _RV1X, ix, iy, iz) = 0.0;
	  MRC_F3(fld, _RV1Y, ix, iy, iz) = 0.0;
	  MRC_F3(fld, _RV1Z, ix, iy, iz) = 0.0;      	  
      } else if((strcmp(sub->pdim, "xz") || (strcmp(sub->pdim,"zx"))) == 1){
	  MRC_F3(fld, _RR1, ix, iy, iz) = sub->n0;
	  if( sqrt((r[0]*r[0]) + (r[2]*r[2])) <= sub->initrad ){	
	    MRC_F3(fld, _UU1 , ix, iy, iz) = sub->pin / (gamma - 1.f) +
	      .5f * (sqr(MRC_F3(fld, _RV1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Z, ix, iy, iz))) / MRC_F3(fld, _RR1, ix, iy, iz) +
	      .5f * (sqr(MRC_F3(fld, _B1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Z, ix, iy, iz)));      
	  } else{	
	    MRC_F3(fld, _UU1 , ix, iy, iz) = sub->pout / (gamma - 1.f) +
	      .5f * (sqr(MRC_F3(fld, _RV1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _RV1Z, ix, iy, iz))) / MRC_F3(fld, _RR1, ix, iy, iz) +
	      .5f * (sqr(MRC_F3(fld, _B1X, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Y, ix, iy, iz)) +
		     sqr(MRC_F3(fld, _B1Z, ix, iy, iz)));      
	  }
	  MRC_F3(fld, _RV1X, ix, iy, iz) = 0.0;
	  MRC_F3(fld, _RV1Y, ix, iy, iz) = 0.0;
	  MRC_F3(fld, _RV1Z, ix, iy, iz) = 0.0;      	  
    } else {           
	  assert(0); /* unknown initial condition */
    }
  } mrc_fld_foreach_end;
}




// ----------------------------------------------------------------------
// ggcm_mhd_ic_hydroblast_descr

#define VAR(x) (void *)offsetof(struct ggcm_mhd_ic_hydroblast, x)
static struct param ggcm_mhd_ic_hydroblast_descr[] = {
  {"initrad", VAR(initrad), PARAM_FLOAT(0.1)},
  {"pin", VAR(pin), PARAM_FLOAT(10.0)},
  {"pout", VAR(pout), PARAM_FLOAT(0.1)},
  {"n0", VAR(n0), PARAM_FLOAT(1.0)},
  {"pdim", VAR(pdim), PARAM_STRING("xy")},  
  {},
};
#undef VAR

// ----------------------------------------------------------------------
// ggcm_mhd_ic_hydroblast_ops

struct ggcm_mhd_ic_ops ggcm_mhd_ic_hydroblast_ops = {
  .name        = "hydroblast",
  .size        = sizeof(struct ggcm_mhd_ic_hydroblast),
  .param_descr = ggcm_mhd_ic_hydroblast_descr,
  .run         = ggcm_mhd_ic_hydroblast_run,
};
