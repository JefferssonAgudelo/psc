
#include "psc_cuda.h"
#include "particles_cuda.h"

#define LOAD_PARTICLE_(pp, d_xi4, d_pxi4, n) do {			\
    (pp).xi[0]         = d_xi4[n].x;					\
    (pp).xi[1]         = d_xi4[n].y;					\
    (pp).xi[2]         = d_xi4[n].z;					\
    (pp).kind_as_float = d_xi4[n].w;					\
    (pp).pxi[0]        = d_pxi4[n].x;					\
    (pp).pxi[1]        = d_pxi4[n].y;					\
    (pp).pxi[2]        = d_pxi4[n].z;					\
    (pp).qni_wni       = d_pxi4[n].w;					\
} while (0)

#define STORE_PARTICLE_POS_(pp, d_xi4, n) do {				\
    d_xi4[n].x = (pp).xi[0];						\
    d_xi4[n].y = (pp).xi[1];						\
    d_xi4[n].z = (pp).xi[2];						\
    d_xi4[n].w = (pp).kind_as_float;					\
} while (0)

#define STORE_PARTICLE_MOM_(pp, d_pxi4, n) do {			\
    d_pxi4[n].x = (pp).pxi[0];					\
    d_pxi4[n].y = (pp).pxi[1];					\
    d_pxi4[n].z = (pp).pxi[2];					\
    d_pxi4[n].w = (pp).qni_wni;					\
} while (0)

#define NO_CHECKERBOARD
//#define DEBUG

#define SW (2)

#include "cuda_common.h"

__device__ int *__d_error_count;

void
set_params(struct cuda_params *prm, struct psc *psc,
	   struct psc_particles *prts, struct psc_fields *pf)
{
  prm->dt = psc->dt;
  for (int d = 0; d < 3; d++) {
    prm->dxi[d] = 1.f / ppsc->dx[d];
  }

  prm->dqs    = .5f * psc->coeff.eta * psc->dt;
  prm->fnqs   = sqr(psc->coeff.alpha) * psc->coeff.cori / psc->coeff.eta;
  prm->fnqys  = psc->dx[1] * prm->fnqs / psc->dt;
  prm->fnqzs  = psc->dx[2] * prm->fnqs / psc->dt;
  assert(psc->nr_kinds <= MAX_KINDS);
  for (int k = 0; k < psc->nr_kinds; k++) {
    prm->dq[k] = prm->dqs * psc->kinds[k].q / psc->kinds[k].m;
  }

  if (prts) {
    struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
    for (int d = 0; d < 3; d++) {
      prm->b_mx[d] = cuda->b_mx[d];
      prm->b_dxi[d] = cuda->b_dxi[d];
    }
  }

  if (pf) {
    for (int d = 0; d < 3; d++) {
      prm->mx[d] = pf->im[d];
      prm->ilg[d] = pf->ib[d];
    }
  }

  check(cudaMalloc(&prm->d_error_count, 1 * sizeof(int)));
  check(cudaMemset(prm->d_error_count, 0, 1 * sizeof(int)));
}

void
free_params(struct cuda_params *prm)
{
  int h_error_count[1];
  check(cudaMemcpy(h_error_count, prm->d_error_count, 1 * sizeof(int),
		   cudaMemcpyDeviceToHost));
  check(cudaFree(prm->d_error_count));
  if (h_error_count[0] != 0) {
    printf("err cnt %d\n", h_error_count[0]);
  }
  assert(h_error_count[0] == 0);
}

// ======================================================================

void
psc_mparticles_cuda_copy_to_dev(struct psc_mparticles *mprts)
{
  struct psc_mparticles_cuda *mprts_cuda = psc_mparticles_cuda(mprts);

  check(cudaMemcpy(mprts_cuda->d_dev, mprts_cuda->h_dev,
		   mprts->nr_patches * sizeof(*mprts_cuda->d_dev),
		   cudaMemcpyHostToDevice));
}

void
cuda_mflds_create(struct cuda_mflds *cuda_mflds, struct psc_mfields *mflds)
{
  cuda_mflds->mflds_cuda = new struct psc_fields *[mflds->nr_patches];
  cuda_mflds->nr_patches = 0;
  for (int p = 0; p < mflds->nr_patches; p++) {
    struct psc_fields *flds = psc_mfields_get_patch(mflds, p);
    if (psc_fields_ops(flds) == &psc_fields_cuda_ops) {
      cuda_mflds->mflds_cuda[cuda_mflds->nr_patches] = flds;
      cuda_mflds->nr_patches++;
    }
  }

  cuda_mflds->h_cp_flds = new struct cuda_patch_flds[cuda_mflds->nr_patches];
  for (int p = 0; p < cuda_mflds->nr_patches; p++) {
    struct psc_fields *flds = cuda_mflds->mflds_cuda[p];
    cuda_mflds->h_cp_flds[p].d_flds = psc_fields_cuda(flds)->d_flds;
  }

  check(cudaMalloc(&cuda_mflds->d_cp_flds,
		   cuda_mflds->nr_patches * sizeof(*cuda_mflds->d_cp_flds)));
  check(cudaMemcpy(cuda_mflds->d_cp_flds, cuda_mflds->h_cp_flds,
		   cuda_mflds->nr_patches * sizeof(*cuda_mflds->d_cp_flds),
		   cudaMemcpyHostToDevice));
}

void
cuda_mflds_destroy(struct cuda_mflds *cuda_mflds)
{
  check(cudaFree(cuda_mflds->d_cp_flds));
  delete[] cuda_mflds->h_cp_flds;
  delete[] cuda_mflds->mflds_cuda;
}

// ======================================================================
// field caching

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
class F3cache {
  real *fld_cache;

public:
  __device__ F3cache(real *_fld_cache, real *d_flds, int l[3],
		     struct cuda_params prm) :
    fld_cache(_fld_cache)
  {
    int ti = threadIdx.x;
    int n = BLOCKSIZE_X * (BLOCKSIZE_Y + 4) * (BLOCKSIZE_Z + 4);
    while (ti < n) {
      int tmp = ti;
      int jx = tmp % BLOCKSIZE_X;
      tmp /= BLOCKSIZE_X;
      int jy = tmp % (BLOCKSIZE_Y + 4) - 2;
      tmp /= BLOCKSIZE_Y + 4;
      int jz = tmp % (BLOCKSIZE_Z + 4) - 2;
      //    tmp /= BLOCKSIZE_Z + 4;
      //    int m = tmp + EX;
      //    printf("n %d ti %d m %d, jx %d,%d,%d\n", n, ti, m, jx, jy, jz);
      // currently it seems faster to do the loop rather than do m by threadidx
      for (int m = EX; m <= HZ; m++) {
	(*this)(m, jx,jy,jz) = F3_DEV_YZ(m, jy+l[1],jz+l[2]);
      }
      ti += blockDim.x;
    }
    __syncthreads();
  }

  __host__ __device__ real operator()(int fldnr, int jx, int jy, int jz) const
  {
    int off = ((((fldnr-EX)
		 *(BLOCKSIZE_Z + 4) + ((jz)-(-2)))
		*(BLOCKSIZE_Y + 4) + ((jy)-(-2)))
	       *1 + ((jx)));
    return fld_cache[off];
  }
  __host__ __device__ real& operator()(int fldnr, int jx, int jy, int jz)
  {
    int off = ((((fldnr-EX)
		 *(BLOCKSIZE_Z + 4) + ((jz)-(-2)))
		*(BLOCKSIZE_Y + 4) + ((jy)-(-2)))
	       *1 + ((jx)));
    return fld_cache[off];
  }
};

// ----------------------------------------------------------------------
// push_xi
//
// advance position using velocity

__device__ static void
push_xi(struct d_particle *p, const real vxi[3], real dt)
{
  int d;
  for (d = 1; d < 3; d++) {
    p->xi[d] += dt * vxi[d];
  }
}

// ----------------------------------------------------------------------
// calc_vxi
//
// calculate velocity from momentum

__device__ static void
calc_vxi(real vxi[3], struct d_particle p)
{
  real root = rsqrtr(real(1.) + sqr(p.pxi[0]) + sqr(p.pxi[1]) + sqr(p.pxi[2]));

  int d;
  for (d = 0; d < 3; d++) {
    vxi[d] = p.pxi[d] * root;
  }
}

// ----------------------------------------------------------------------
// push_pxi_dt
//
// advance moments according to EM fields

__device__ static void
push_pxi_dt(struct d_particle *p,
	    real exq, real eyq, real ezq, real hxq, real hyq, real hzq,
	    struct cuda_params prm)
{
  int kind = __float_as_int(p->kind_as_float);
  real dq = prm.dq[kind];
  real pxm = p->pxi[0] + dq*exq;
  real pym = p->pxi[1] + dq*eyq;
  real pzm = p->pxi[2] + dq*ezq;
  
  real root = dq * rsqrtr(real(1.) + sqr(pxm) + sqr(pym) + sqr(pzm));
  real taux = hxq * root, tauy = hyq * root, tauz = hzq * root;
  
  real tau = real(1.) / (real(1.) + sqr(taux) + sqr(tauy) + sqr(tauz));
  real pxp = ( (real(1.) + sqr(taux) - sqr(tauy) - sqr(tauz)) * pxm
	       +(real(2.)*taux*tauy + real(2.)*tauz)*pym
	       +(real(2.)*taux*tauz - real(2.)*tauy)*pzm)*tau;
  real pyp = ( (real(2.)*taux*tauy - real(2.)*tauz)*pxm
	       +(real(1.) - sqr(taux) + sqr(tauy) - sqr(tauz)) * pym
	       +(real(2.)*tauy*tauz + real(2.)*taux)*pzm)*tau;
  real pzp = ( (real(2.)*taux*tauz + real(2.)*tauy)*pxm
	       +(real(2.)*tauy*tauz - real(2.)*taux)*pym
	       +(real(1.) - sqr(taux) - sqr(tauy) + sqr(tauz))*pzm)*tau;
  
  p->pxi[0] = pxp + dq * exq;
  p->pxi[1] = pyp + dq * eyq;
  p->pxi[2] = pzp + dq * ezq;
}

#define OFF(g, d) o##g[d]
  
__device__ static real
ip1_to_grid_0(real h)
{
  return real(1.) - h;
}

__device__ static real
ip1_to_grid_p(real h)
{
  return h;
}

#define INTERP_FIELD_1ST(cache, exq, fldnr, g1, g2)			\
  do {									\
    int ddy = l##g1[1]-l0[1], ddz = l##g2[2]-l0[2];			\
    /* printf("C %g [%d,%d,%d]\n", F3C(fldnr, 0, ddy, ddz), 0, ddy, ddz); */ \
    exq =								\
      ip1_to_grid_0(OFF(g1, 1)) * ip1_to_grid_0(OFF(g2, 2)) *		\
      cache(fldnr, 0, ddy+0, ddz+0) +					\
      ip1_to_grid_p(OFF(g1, 1)) * ip1_to_grid_0(OFF(g2, 2)) *		\
      cache(fldnr, 0, ddy+1, ddz+0) +					\
      ip1_to_grid_0(OFF(g1, 1)) * ip1_to_grid_p(OFF(g2, 2)) *		\
      cache(fldnr, 0, ddy+0, ddz+1) +					\
      ip1_to_grid_p(OFF(g1, 1)) * ip1_to_grid_p(OFF(g2, 2)) *		\
      cache(fldnr, 0, ddy+1, ddz+1);					\
  } while(0)

// ----------------------------------------------------------------------
// push_part_one
//
// push one particle

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
__device__ static void
push_part_one(int n, float4 *d_xi4, float4 *d_pxi4,
	      const F3cache<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> &cached_flds, int l0[3],
	      struct cuda_params prm)
{
  struct d_particle p;
  LOAD_PARTICLE_(p, d_xi4, d_pxi4, n);

  // here we have x^{n+.5}, p^n
  
  // field interpolation

  int lh[3], lg[3];
  real oh[3], og[3];
  find_idx_off_1st(p.xi, lh, oh, real(-.5), prm.dxi);
  find_idx_off_1st(p.xi, lg, og, real(0.), prm.dxi);

  real exq, eyq, ezq, hxq, hyq, hzq;
  INTERP_FIELD_1ST(cached_flds, exq, EX, g, g);
  INTERP_FIELD_1ST(cached_flds, eyq, EY, h, g);
  INTERP_FIELD_1ST(cached_flds, ezq, EZ, g, h);
  INTERP_FIELD_1ST(cached_flds, hxq, HX, h, h);
  INTERP_FIELD_1ST(cached_flds, hyq, HY, g, h);
  INTERP_FIELD_1ST(cached_flds, hzq, HZ, h, g);

  // x^(n+0.5), p^n -> x^(n+0.5), p^(n+1.0) 
  
  push_pxi_dt(&p, exq, eyq, ezq, hxq, hyq, hzq, prm);

  STORE_PARTICLE_MOM_(p, d_pxi4, n);
}

// ----------------------------------------------------------------------
// push_mprts_p1
//
// push particles

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
__global__ static void
push_mprts_p1(struct cuda_params prm, float4 *d_xi4, float4 *d_pxi4,
	      unsigned int *d_off,
	      struct cuda_patch_flds *d_cp_flds)
{
  __d_error_count = prm.d_error_count;
  int tid = threadIdx.x;

  int block_pos[3];
  block_pos[1] = blockIdx.x;
  block_pos[2] = blockIdx.y % prm.b_mx[2];
  int p = blockIdx.y / prm.b_mx[2];

  int ci[3];
  ci[0] = 0;
  ci[1] = block_pos[1] * BLOCKSIZE_Y;
  ci[2] = block_pos[2] * BLOCKSIZE_Z;
  int bid = block_pos_to_block_idx(block_pos, prm.b_mx);

  int block_begin = d_off[bid + p * prm.b_mx[1] * prm.b_mx[2]];
  int block_end   = d_off[bid + p * prm.b_mx[1] * prm.b_mx[2] + 1];

  extern __shared__ real fld_cache[];

  F3cache<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> cached_flds(fld_cache, d_cp_flds[p].d_flds, ci, prm);
  
  for (int n = block_begin + tid; n < block_end; n += THREADS_PER_BLOCK) {
    push_part_one(n, d_xi4, d_pxi4, cached_flds, ci, prm);
  }
}

// ----------------------------------------------------------------------
// cuda_push_mprts_a

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
static void
cuda_push_mprts_a(struct psc_mparticles *mprts, struct cuda_mflds *cuda_mflds)
{
  struct psc_mparticles_cuda *mprts_cuda = psc_mparticles_cuda(mprts);

  if (mprts->nr_patches == 0) {
    return;
  }

  struct cuda_params prm;
  set_params(&prm, ppsc, psc_mparticles_get_patch(mprts, 0), cuda_mflds->mflds_cuda[0]);
  
  // FIXME, why is this dynamic?
  unsigned int shared_size = 6 * 1 * (BLOCKSIZE_Y + 4) * (BLOCKSIZE_Z + 4) * sizeof(real);
  
  dim3 dimGrid(prm.b_mx[1], prm.b_mx[2] * mprts->nr_patches);
  
  push_mprts_p1<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z>
    <<<dimGrid, THREADS_PER_BLOCK, shared_size>>>
    (prm, mprts_cuda->d_xi4, mprts_cuda->d_pxi4, mprts_cuda->d_off,
     cuda_mflds->d_cp_flds);
  cuda_sync_if_enabled();
  
  free_params(&prm);
}

// ======================================================================

// FIXME -> common.c

__device__ static void
find_idx_off_pos_1st(const real xi[3], int j[3], real h[3], real pos[3], real shift,
		     struct cuda_params prm)
{
  int d;
  for (d = 0; d < 3; d++) {
    pos[d] = xi[d] * prm.dxi[d] + shift;
    j[d] = cuda_fint(pos[d]);
    h[d] = pos[d] - j[d];
  }
}

__shared__ volatile bool do_read;
__shared__ volatile bool do_write;
__shared__ volatile bool do_reduce;
__shared__ volatile bool do_calc_j;

// OPT: take i < cell_end condition out of load
// OPT: reduce two at a time
// OPT: try splitting current calc / measuring by itself
// OPT: get rid of block_stride

__shared__ int ci0[3]; // cell index of lower-left cell in block

#define WARPS_PER_BLOCK (THREADS_PER_BLOCK / 32)

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
class SCurr {
  real *scurr;

public:
  __device__ SCurr(real *_scurr) :
    scurr(_scurr)
  {
  }

  __device__ void zero()
  {
    const int blockstride = ((((BLOCKSIZE_Y + 2*SW) * (BLOCKSIZE_Z + 2*SW) + 31) / 32) * 32);
    int i = threadIdx.x;
    int N = blockstride * WARPS_PER_BLOCK;
    while (i < N) {
      scurr[i] = real(0.);
      i += THREADS_PER_BLOCK;
    }
  }

  __device__ void add_to_fld(real *d_flds, int m, struct cuda_params prm)
  {
    int i = threadIdx.x;
    int stride = (BLOCKSIZE_Y + 2*SW) * (BLOCKSIZE_Z + 2*SW);
    while (i < stride) {
      int rem = i;
      int jz = rem / (BLOCKSIZE_Y + 2*SW);
      rem -= jz * (BLOCKSIZE_Y + 2*SW);
      int jy = rem;
      jz -= SW;
      jy -= SW;
      real val = real(0.);
      // FIXME, opt
      for (int wid = 0; wid < WARPS_PER_BLOCK; wid++) {
	val += (*this)(wid, jy, jz);
      }
      F3_DEV_YZ(JXI+m, jy+ci0[1],jz+ci0[2]) += val;
      i += THREADS_PER_BLOCK;
    }
  }

  __device__ real operator()(int wid, int jy, int jz) const
  {
    const int blockstride = ((((BLOCKSIZE_Y + 2*SW) * (BLOCKSIZE_Z + 2*SW) + 31) / 32) * 32);
    unsigned int off = (jz + SW) * (BLOCKSIZE_Y + 2*SW) + jy + SW + wid * blockstride;
#ifdef DEBUG
    if (off >= WARPS_PER_BLOCK * blockstride) {
      (*__d_error_count)++;
      off = 0;
    }
#endif

    return scurr[off];
  }
  __device__ real& operator()(int wid, int jy, int jz)
  {
    const int blockstride = ((((BLOCKSIZE_Y + 2*SW) * (BLOCKSIZE_Z + 2*SW) + 31) / 32) * 32);
    unsigned int off = (jz + SW) * (BLOCKSIZE_Y + 2*SW) + jy + SW + wid * blockstride;
#ifdef DEBUG
    if (off >= WARPS_PER_BLOCK * blockstride) {
      (*__d_error_count)++;
      off = 0;
    }
#endif

    return scurr[off];
  }
  __device__ real operator()(int jy, int jz) const
  {
    return (*this)(threadIdx.x >> 5, jy, jz);
  }
  __device__ real& operator()(int jy, int jz)
  {
    return (*this)(threadIdx.x >> 5, jy, jz);
  }
};

// ======================================================================

// ----------------------------------------------------------------------
// current_add

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
__device__ static void
current_add(SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> &scurr, int jy, int jz, real val)
{
  float *addr = &scurr(jy, jz);
  if (!do_write)
    return;

  if (do_reduce) {
#if __CUDA_ARCH__ >= 200 // for Fermi, atomicAdd supports floats
    atomicAdd(addr, val);
#else
#if 0
    while ((val = atomicExch(addr, atomicExch(addr, 0.0f)+val))!=0.0f);
#else
    int lid = threadIdx.x & 31;
    for (int i = 0; i < 32; i++) {
      if (lid == i) {
	*addr += val;
      }
    }
#endif
#endif
  } else {
    *addr += val;
  }
}

// ----------------------------------------------------------------------
// yz_calc_jx

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
__device__ static void
yz_calc_jx(int i, float4 *d_xi4, float4 *d_pxi4,
	   SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> &scurr,
	   struct cuda_params prm)
{
  struct d_particle p;
  if (do_read) {
    LOAD_PARTICLE_(p, d_xi4, d_pxi4, i);
  }

  real vxi[3];
  calc_vxi(vxi, p);
  push_xi(&p, vxi, .5f * prm.dt);

  if (do_calc_j) {
    real fnqx = vxi[0] * p.qni_wni * prm.fnqs;
    
    int lf[3];
    real of[3];
    find_idx_off_1st(p.xi, lf, of, real(0.), prm.dxi);
    lf[1] -= ci0[1];
    lf[2] -= ci0[2];
    current_add(scurr, lf[1]  , lf[2]  , (1.f - of[1]) * (1.f - of[2]) * fnqx);
    current_add(scurr, lf[1]+1, lf[2]  , (      of[1]) * (1.f - of[2]) * fnqx);
    current_add(scurr, lf[1]  , lf[2]+1, (1.f - of[1]) * (      of[2]) * fnqx);
    current_add(scurr, lf[1]+1, lf[2]+1, (      of[1]) * (      of[2]) * fnqx);
  }
}

// ----------------------------------------------------------------------
// yz_calc_jy

__device__ static void
calc_dx1(real dx1[2], real x[2], real dx[2], int off[2])
{
  if (off[1] == 0) {
    dx1[0] = .5f * off[0] - x[0];
    if (dx[0] != 0.f)
      dx1[1] = dx[1] / dx[0] * dx1[0];
    else
      dx1[1] = 0.f;
  } else {
    dx1[1] = .5f * off[1] - x[1];
    if (dx[1] != 0.f)
      dx1[0] = dx[0] / dx[1] * dx1[1];
    else
      dx1[0] = 0.f;
  }
}

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
__device__ static void
curr_2d_vb_cell(int i[2], real x[2], real dx[2], real qni_wni,
		real dxt[2], int off[2],
		SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> &scurr_y,
		SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> &scurr_z,
		struct cuda_params prm)
{
  real fnqy = qni_wni * prm.fnqys;
  real fnqz = qni_wni * prm.fnqzs;
  current_add(scurr_y, i[0],i[1]  , fnqy * dx[0] * (.5f - x[1] - .5f * dx[1]));
  current_add(scurr_y, i[0],i[1]+1, fnqy * dx[0] * (.5f + x[1] + .5f * dx[1]));
  current_add(scurr_z, i[0],i[1]  , fnqz * dx[1] * (.5f - x[0] - .5f * dx[0]));
  current_add(scurr_z, i[0]+1,i[1], fnqz * dx[1] * (.5f + x[0] + .5f * dx[0]));
  if (dxt) {
    dxt[0] -= dx[0];
    dxt[1] -= dx[1];
    x[0] += dx[0] - off[0];
    x[1] += dx[1] - off[1];
    i[0] += off[0];
    i[1] += off[1];
  }
}

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
__device__ static void
yz_calc_jyjz(int i, float4 *d_xi4, float4 *d_pxi4,
	     SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> &scurr_y,
	     SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> &scurr_z,
	     struct cuda_params prm)
{
  struct d_particle p;

  // OPT/FIXME, is it really better to reload the particle?
  if (do_read) {
    LOAD_PARTICLE_(p, d_xi4, d_pxi4, i);
  }

  if (do_calc_j) {
    real vxi[3];
    real h0[3], h1[3];
    real xm[3], xp[3];
    
    int j[3], k[3];
    calc_vxi(vxi, p);
    
    find_idx_off_pos_1st(p.xi, j, h0, xm, real(0.), prm);

    // x^(n+0.5), p^(n+1.0) -> x^(n+1.5), p^(n+1.0) 
    push_xi(&p, vxi, prm.dt);
    STORE_PARTICLE_POS_(p, d_xi4, i);
#if 0
    {
      unsigned int block_pos_y = cuda_fint(p.xi[1] * prm.b_dxi[1]);
      unsigned int block_pos_z = cuda_fint(p.xi[2] * prm.b_dxi[2]);

      int block_idx;
      if (block_pos_y >= prm.b_mx[1] || block_pos_z >= prm.b_mx[2]) {
	block_idx = prm.b_mx[1] * prm.b_mx[2];
      } else {
	block_idx = block_pos_z * prm.b_mx[1] + block_pos_y;
      }
      d_dev.bidx[i] = block_idx;
    }
#endif
    find_idx_off_pos_1st(p.xi, k, h1, xp, real(0.), prm);
    
    int idiff[2] = { k[1] - j[1], k[2] - j[2] };
    real dx[2] = { xp[1] - xm[1], xp[2] - xm[2] };
    real x[2] = { xm[1] - (j[1] + real(.5)), xm[2] - (j[2] + real(.5)) };
    int i[2] = { j[1] - ci0[1], j[2] - ci0[2] };
  
    int off[2];
    int first_dir, second_dir = -1;
    // FIXME, make sure we never div-by-zero?
    if (idiff[0] == 0 && idiff[1] == 0) {
      first_dir = -1;
    } else if (idiff[0] == 0) {
      first_dir = 1;
    } else if (idiff[1] == 0) {
      first_dir = 0;
    } else {
      real dx1[2];
      dx1[0] = .5f * idiff[0] - x[0];
      dx1[1] = dx[1] / dx[0] * dx1[0];
      if (fabsf(x[1] + dx1[1]) > .5f) {
	first_dir = 1;
      } else {
	first_dir = 0;
      }
      second_dir = 1 - first_dir;
    }
    
    if (first_dir >= 0) {
      if (first_dir == 0) {
	off[0] = idiff[0];
	off[1] = 0;
      } else {
	off[0] = 0;
	off[1] = idiff[1];
      }
      real dx1[2];
      calc_dx1(dx1, x, dx, off);
      curr_2d_vb_cell(i, x, dx1, p.qni_wni, dx, off, scurr_y, scurr_z, prm);
    }
    
    if (second_dir >= 0) {
      off[0] = idiff[0] - off[0];
      off[1] = idiff[1] - off[1];
      real dx1[2];
      calc_dx1(dx1, x, dx, off);
      curr_2d_vb_cell(i, x, dx1, p.qni_wni, dx, off, scurr_y, scurr_z, prm);
    }
    
    curr_2d_vb_cell(i, x, dx, p.qni_wni, NULL, NULL, scurr_y, scurr_z, prm);
  }
}

// ======================================================================

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
__global__ static void
push_mprts_p3(int block_start, struct cuda_params prm, float4 *d_xi4, float4 *d_pxi4,
	      unsigned int *d_off, struct cuda_patch_flds *d_cp_flds)
{
  __d_error_count = prm.d_error_count;
  do_read = true;
  do_reduce = true;
  do_write = true;
  do_calc_j = true;

  const int block_stride = (((BLOCKSIZE_Y + 2*SW) * (BLOCKSIZE_Z + 2*SW) + 31) / 32) * 32;
  __shared__ real _scurrx[WARPS_PER_BLOCK * block_stride];
  __shared__ real _scurry[WARPS_PER_BLOCK * block_stride];
  __shared__ real _scurrz[WARPS_PER_BLOCK * block_stride];

  SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> scurr_x(_scurrx);
  SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> scurr_y(_scurry);
  SCurr<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z> scurr_z(_scurrz);

  if (do_write) {
    scurr_x.zero();
    scurr_y.zero();
    scurr_z.zero();
  }

  int grid_dim_y = (prm.b_mx[2] + 1) / 2;
  int tid = threadIdx.x;
  int block_pos[3];
  block_pos[1] = blockIdx.x * 2;
  block_pos[2] = (blockIdx.y % grid_dim_y) * 2;
  block_pos[1] += block_start & 1;
  block_pos[2] += block_start >> 1;
  if (block_pos[1] >= prm.b_mx[1] ||
      block_pos[2] >= prm.b_mx[2])
    return;

  int p = blockIdx.y / grid_dim_y;

  int bid = block_pos_to_block_idx(block_pos, prm.b_mx);
  __shared__ int s_block_end;
  if (tid == 0) {
    ci0[0] = 0;
    ci0[1] = block_pos[1] * BLOCKSIZE_Y;
    ci0[2] = block_pos[2] * BLOCKSIZE_Z;
    s_block_end = d_off[bid + p * prm.b_mx[1] * prm.b_mx[2] + 1];
  }
  __syncthreads();

  int block_begin = d_off[bid + p * prm.b_mx[1] * prm.b_mx[2]];

  for (int i = block_begin + tid; i < s_block_end; i += THREADS_PER_BLOCK) {
    yz_calc_jx(i, d_xi4, d_pxi4, scurr_x, prm);
    yz_calc_jyjz(i, d_xi4, d_pxi4, scurr_y, scurr_z, prm);
  }
  
  if (do_write) {
    __syncthreads();
    scurr_x.add_to_fld(d_cp_flds[p].d_flds, 0, prm);
    scurr_y.add_to_fld(d_cp_flds[p].d_flds, 1, prm);
    scurr_z.add_to_fld(d_cp_flds[p].d_flds, 2, prm);
  }
}

// ----------------------------------------------------------------------
// cuda_push_mprts_b

template<int BLOCKSIZE_X, int BLOCKSIZE_Y, int BLOCKSIZE_Z>
static void
cuda_push_mprts_b(struct psc_mparticles *mprts, struct cuda_mflds *cuda_mflds)
{
  struct psc_mparticles_cuda *mprts_cuda = psc_mparticles_cuda(mprts);

  if (mprts->nr_patches == 0)
    return;

  struct cuda_params prm;
  set_params(&prm, ppsc, psc_mparticles_get_patch(mprts, 0), cuda_mflds->mflds_cuda[0]);
  
  for (int p = 0; p < cuda_mflds->nr_patches; p++) {
    unsigned int size = prm.mx[0] * prm.mx[1] * prm.mx[2];
    check(cudaMemset(cuda_mflds->h_cp_flds[p].d_flds + JXI * size, 0,
		     3 * size * sizeof(*cuda_mflds->h_cp_flds[p].d_flds)));
  }
  
  dim3 dimGrid((prm.b_mx[1] + 1) / 2, ((prm.b_mx[2] + 1) / 2) * mprts->nr_patches);
  
  for (int block_start = 0; block_start < 4; block_start++) {
    push_mprts_p3<BLOCKSIZE_X, BLOCKSIZE_Y, BLOCKSIZE_Z>
      <<<dimGrid, THREADS_PER_BLOCK>>>
      (block_start, prm, mprts_cuda->d_xi4, mprts_cuda->d_pxi4, mprts_cuda->d_off,
       cuda_mflds->d_cp_flds);
    cuda_sync_if_enabled();
    }
  
  free_params(&prm);
}

// ======================================================================

EXTERN_C void
yz2x2_1vb_cuda_push_part_p2(struct psc_particles *prts, struct psc_fields *pf)
{
  assert(0);
  //  cuda_push_part_p2<1, 2, 2>(prts, pf);
}

EXTERN_C void
yz2x2_1vb_cuda_push_part_p3(struct psc_particles *prts, struct psc_fields *pf, real *dummy,
			    int block_stride)
{
  assert(0);
  //  cuda_push_part_p3<1, 2, 2>(prts, pf);
}

EXTERN_C void
yz8x8_1vb_cuda_push_part_p2(struct psc_particles *prts, struct psc_fields *pf)
{
  assert(0);
  //  cuda_push_part_p2<1, 8, 8>(prts, pf);
}

EXTERN_C void
yz8x8_1vb_cuda_push_part_p3(struct psc_particles *prts, struct psc_fields *pf, real *dummy,
			    int block_stride)
{
  assert(0);
  //  cuda_push_part_p3<1, 8, 8>(prts, pf);
}






EXTERN_C void
yz4x4_1vb_cuda_push_mprts_a(struct psc_mparticles *mprts, struct psc_mfields *mflds)
{
  struct cuda_mflds cuda_mflds;
  psc_mparticles_cuda_copy_to_dev(mprts);
  cuda_mflds_create(&cuda_mflds, mflds);
  // FIXME, should make sure they're compatible

  cuda_push_mprts_a<1, 4, 4>(mprts, &cuda_mflds);

  cuda_mflds_destroy(&cuda_mflds);
}

EXTERN_C void
yz4x4_1vb_cuda_push_mprts_b(struct psc_mparticles *mprts, struct psc_mfields *mflds)
{
  struct cuda_mflds cuda_mflds;
  cuda_mflds_create(&cuda_mflds, mflds);

  cuda_push_mprts_b<1, 4, 4>(mprts, &cuda_mflds);

  cuda_mflds_destroy(&cuda_mflds);
}
