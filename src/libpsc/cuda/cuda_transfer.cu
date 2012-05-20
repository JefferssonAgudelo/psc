
#include "psc_cuda.h"

#include <mrc_profile.h>

EXTERN_C void
cuda_init(int rank)
{
  static bool inited;
  if (!inited) {
    inited = true;
    cudaSetDevice(rank % 3);
  }
}

// FIXME, hardcoding is bad, needs to be consistent, etc...
#define BND  (3)
#define MAX_BND_COMPONENTS (3)

EXTERN_C void
__particles_cuda_alloc(struct psc_particles *prts, bool need_block_offsets,
		       bool need_cell_offsets)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  int n_alloced = prts->n_part * 1.2; // FIXME, need to handle realloc eventualy
  cuda->n_alloced = n_alloced;
  particles_cuda_dev_t *d_part = &cuda->d_part;

  const int cells_per_block = cuda->blocksize[0] * cuda->blocksize[1] * cuda->blocksize[2];

  check(cudaMalloc((void **) &d_part->xi4, n_alloced * sizeof(float4)));
  check(cudaMalloc((void **) &d_part->pxi4, n_alloced * sizeof(float4)));

  check(cudaMalloc((void **) &d_part->alt_xi4, n_alloced * sizeof(float4)));
  check(cudaMalloc((void **) &d_part->alt_pxi4, n_alloced * sizeof(float4)));

  if (need_block_offsets) {
    check(cudaMalloc((void **) &d_part->offsets, 
		     (cuda->nr_blocks + 1) * sizeof(int)));
    check(cudaMemcpy(&d_part->offsets[cuda->nr_blocks], &prts->n_part, sizeof(int),
		     cudaMemcpyHostToDevice));
  }

  if (need_cell_offsets) {
    check(cudaMalloc((void **) &d_part->c_offsets, 
		     (cuda->nr_blocks * cells_per_block + 1) * sizeof(int)));
  }

  check(cudaMalloc((void **) &d_part->c_pos, 
		   (cuda->nr_blocks * cells_per_block * 3) * sizeof(int)));
}

EXTERN_C void
__particles_cuda_to_device(struct psc_particles *prts, float4 *xi4, float4 *pxi4,
			   int *offsets, int *c_offsets, int *c_pos)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  int n_part = prts->n_part;
  particles_cuda_dev_t *d_part = &cuda->d_part;

  const int cells_per_block = cuda->blocksize[0] * cuda->blocksize[1] * cuda->blocksize[2];

  assert(n_part <= cuda->n_alloced);
  check(cudaMemcpy(d_part->xi4, xi4, n_part * sizeof(*xi4),
		   cudaMemcpyHostToDevice));
  check(cudaMemcpy(d_part->pxi4, pxi4, n_part * sizeof(*pxi4),
		   cudaMemcpyHostToDevice));
  if (offsets) {
    check(cudaMemcpy(d_part->offsets, offsets,
		     (cuda->nr_blocks + 1) * sizeof(int), cudaMemcpyHostToDevice));
  }
  if (c_offsets) {
    check(cudaMemcpy(d_part->c_offsets,c_offsets,
		     (cuda->nr_blocks * cells_per_block + 1) * sizeof(int),
		     cudaMemcpyHostToDevice));
  }
  if (c_pos) {
    check(cudaMemcpy(d_part->c_pos, c_pos,
		     (cuda->nr_blocks * cells_per_block * 3) * sizeof(int),
		     cudaMemcpyHostToDevice));
  }
}

EXTERN_C void
__particles_cuda_to_device_range(struct psc_particles *prts, float4 *xi4, float4 *pxi4,
				 int start, int end)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  particles_cuda_dev_t *d_part = &cuda->d_part;

  check(cudaMemcpy(d_part->xi4 + start, xi4, (end - start) * sizeof(*xi4),
		   cudaMemcpyHostToDevice));
  check(cudaMemcpy(d_part->pxi4 + start, pxi4, (end - start) * sizeof(*pxi4),
		   cudaMemcpyHostToDevice));
}

EXTERN_C void
__particles_cuda_from_device(struct psc_particles *prts, float4 *xi4, float4 *pxi4)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  int n_part = prts->n_part;
  particles_cuda_dev_t *d_part = &cuda->d_part;

  assert(n_part <= cuda->n_alloced);
  check(cudaMemcpy(xi4, d_part->xi4, n_part * sizeof(*xi4),
		   cudaMemcpyDeviceToHost));
  check(cudaMemcpy(pxi4, d_part->pxi4, n_part * sizeof(*pxi4),
		   cudaMemcpyDeviceToHost));
}

EXTERN_C void
__particles_cuda_from_device_range(struct psc_particles *prts, float4 *xi4, float4 *pxi4,
				   int start, int end)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  particles_cuda_dev_t *d_part = &cuda->d_part;

  check(cudaMemcpy(xi4, d_part->xi4 + start, (end - start) * sizeof(*xi4),
		   cudaMemcpyDeviceToHost));
  check(cudaMemcpy(pxi4, d_part->pxi4 + start, (end - start) * sizeof(*pxi4),
		   cudaMemcpyDeviceToHost));
}

EXTERN_C void
__particles_cuda_free(struct psc_particles *prts)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  particles_cuda_dev_t *d_part = &cuda->d_part;

  check(cudaFree(d_part->xi4));
  check(cudaFree(d_part->pxi4));
  check(cudaFree(d_part->alt_xi4));
  check(cudaFree(d_part->alt_pxi4));
  check(cudaFree(d_part->offsets));
  check(cudaFree(d_part->c_offsets));
  check(cudaFree(d_part->c_pos));
}

EXTERN_C void
cuda_copy_offsets_from_dev(struct psc_particles *prts, unsigned int *h_offsets)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  check(cudaMemcpy(h_offsets, cuda->d_part.offsets, (cuda->nr_blocks + 1) * sizeof(*h_offsets),
		   cudaMemcpyDeviceToHost));
}

EXTERN_C void
cuda_copy_offsets_to_dev(struct psc_particles *prts, unsigned int *h_offsets)
{
  struct psc_particles_cuda *cuda = psc_particles_cuda(prts);
  check(cudaMemcpy(cuda->d_part.offsets, h_offsets, (cuda->nr_blocks + 1) * sizeof(*h_offsets),
		   cudaMemcpyHostToDevice));
}

EXTERN_C void
__fields_cuda_alloc(fields_cuda_t *pf)
{
  assert(!ppsc->domain.use_pml);

  unsigned int size = pf->im[0] * pf->im[1] * pf->im[2];
  check(cudaMalloc((void **) &pf->d_flds, pf->nr_comp * size * sizeof(float)));

  if (pf->im[0] == 1 + 2*BND) {
    int B = 2*BND;
    unsigned int buf_size = 2*B * (pf->im[1] + pf->im[2] - 2*B);
    pf->h_bnd_buf = new real[MAX_BND_COMPONENTS * buf_size];
    check(cudaMalloc((void **) &pf->d_bnd_buf,
		     MAX_BND_COMPONENTS * buf_size * sizeof(*pf->d_bnd_buf)));
  }
}

EXTERN_C void
__fields_cuda_free(fields_cuda_t *pf)
{
  check(cudaFree(pf->d_flds));

  if (pf->im[0] == 1 + 2*BND) {
    delete[] pf->h_bnd_buf;
    check(cudaFree(pf->d_bnd_buf));
  }
}

EXTERN_C void
__fields_cuda_to_device(fields_cuda_t *pf, real *h_flds, int mb, int me)
{
  unsigned int size = pf->im[0] * pf->im[1] * pf->im[2];
  check(cudaMemcpy(pf->d_flds + mb * size,
		   h_flds + mb * size,
		   (me - mb) * size * sizeof(float),
		   cudaMemcpyHostToDevice));
}

EXTERN_C void
__fields_cuda_from_device(fields_cuda_t *pf, real *h_flds, int mb, int me)
{
  unsigned int size = pf->im[0] * pf->im[1] * pf->im[2];
  check(cudaMemcpy(h_flds + mb * size,
		   pf->d_flds + mb * size,
		   (me - mb) * size * sizeof(float),
		   cudaMemcpyDeviceToHost));
}

// ======================================================================

enum {
  PACK,
  UNPACK,
};

// ======================================================================
// fields_device_pack

// FIXME/OPT: can probably be accelerated by making component the fast index

template<int B, int what>
__global__ static void
k_fields_device_pack_yz(real *d_buf, real *d_flds, int gmy, int gmz, int mm)
{
  unsigned int buf_size = 2*B * (gmy + gmz - 2*B);
  int gmx = 2*BND + 1;
  int jx = BND;
  int tid = threadIdx.x + blockIdx.x * THREADS_PER_BLOCK;
  int n_threads = mm * buf_size;
  if (tid >= n_threads)
    return;

  int n = tid;
  int m = n / buf_size; n -= m * buf_size;
  int jz, jy;
  if (n < B * gmy) {
    jz = n / gmy; n -= jz * gmy;
    jy = n;
  } else if (n < B * gmy + (gmz - 2*B) * 2*B) {
    n -= B * gmy;
    jz = n / (2*B); n -= jz * 2*B;
    if (n < B) {
      jy = n;
    } else {
      jy = n + gmy - 2*B;
    }
    jz += B;
  } else {
    n -= B * gmy + (gmz - 2*B) * 2*B;
    jz = n / gmy; n -= jz * gmy;
    jy = n;
    jz += gmz - B;
  }
  
  // FIXME, should use F3_DEV_YZ
  if (what == PACK) {
    d_buf[tid] = d_flds[((m * gmz + jz) * gmy + jy) * gmx + jx];
  } else if (what == UNPACK) {
    d_flds[((m * gmz + jz) * gmy + jy) * gmx + jx] = d_buf[tid]; 
  }
}

template<int B, bool pack>
static void
fields_device_pack_yz(fields_cuda_t *pf, int mb, int me)
{
  unsigned int size = pf->im[0] * pf->im[1] * pf->im[2];
  int gmy = pf->im[1], gmz = pf->im[2];
  unsigned int buf_size = 2*B * (gmy + gmz - 2*B);
  int n_threads = buf_size * (me - mb);

  dim3 dimGrid((n_threads + (THREADS_PER_BLOCK - 1)) / THREADS_PER_BLOCK);
  dim3 dimBlock(THREADS_PER_BLOCK);

  k_fields_device_pack_yz<B, pack> <<<dimGrid, dimBlock>>>
    (pf->d_bnd_buf, pf->d_flds + mb * size, gmy, gmz, me - mb);
}

// ======================================================================
// fields_host_pack

#define WHAT do {					\
    if (what == PACK) {					\
      h_buf[tid++] = F3_CF_0(cf, m, 0,jy,jz);		\
    } else if (what == UNPACK) {			\
      F3_CF_0(cf, m, 0,jy,jz) = h_buf[tid++];		\
    }							\
  } while(0)

template<int B, int what>
static void
fields_host_pack_yz(struct cuda_fields_ctx *cf, real *h_buf, int mb, int me)
{
  int gmy = cf->im[1], gmz = cf->im[2];
  int tid = 0;
  for (int m = 0; m < me - mb; m++) {
    for (int jz = 0; jz < B; jz++) {
      for (int jy = 0; jy < gmy; jy++) {
	WHAT;
      }
    }
    for (int jz = B; jz < gmz - B; jz++) {
      for (int jy = 0; jy < B; jy++) {
	WHAT;
      }
      for (int jy = gmy - B; jy < gmy; jy++) {
	WHAT;
      }
    }
    for (int jz = gmz - B; jz < gmz; jz++) {
      for (int jy = 0; jy < gmy; jy++) {
	WHAT;
      }
    }
  }
}

template<int B>
static void
__fields_cuda_from_device_yz(fields_cuda_t *pf, struct cuda_fields_ctx *cf, int mb, int me)
{
  int gmy = pf->im[1], gmz = pf->im[2];
  unsigned int buf_size = 2*B * (gmy + gmz - 2*B);
  assert(me - mb <= MAX_BND_COMPONENTS);
  assert(pf->ib[1] == -BND);
  assert(pf->im[1] >= 2 * B);
  assert(pf->im[2] >= 2 * B);

  static int pr1, pr2, pr3;
  if (!pr1) {
    pr1 = prof_register("field_device_pack", 1., 0, 0);
    pr2 = prof_register("cuda_memcpy", 1., 0, 0);
    pr3 = prof_register("field_host_unpack", 1., 0, 0);
  }

  prof_start(pr1);
  fields_device_pack_yz<B, PACK>(pf, mb, me);
  cuda_sync_if_enabled();
  prof_stop(pr1);
  prof_start(pr2);
  check(cudaMemcpy(pf->h_bnd_buf, pf->d_bnd_buf,
		   (me - mb) * buf_size * sizeof(*pf->h_bnd_buf), cudaMemcpyDeviceToHost));
  prof_stop(pr2);
  prof_start(pr3);
  fields_host_pack_yz<B, UNPACK>(cf, pf->h_bnd_buf, mb, me);
  prof_stop(pr3);
}

template<int B>
static void
__fields_cuda_to_device_yz(fields_cuda_t *pf, struct cuda_fields_ctx *cf, int mb, int me)
{
  int gmy = pf->im[1], gmz = pf->im[2];
  unsigned int buf_size = 2*B * (gmy + gmz - 2*B);
  assert(me - mb <= MAX_BND_COMPONENTS);
  assert(pf->ib[1] == -BND);
  assert(pf->im[1] >= 2 * B);
  assert(pf->im[2] >= 2 * B);

  static int pr1, pr2, pr3;
  if (!pr1) {
    pr1 = prof_register("field_host_pack", 1., 0, 0);
    pr2 = prof_register("cuda_memcpy", 1., 0, 0);
    pr3 = prof_register("field_device_unpack", 1., 0, 0);
  }

  prof_start(pr1);
  fields_host_pack_yz<B, PACK>(cf, pf->h_bnd_buf, mb, me);
  prof_stop(pr1);
  prof_start(pr2);
  check(cudaMemcpy(pf->d_bnd_buf, pf->h_bnd_buf,
		   (me - mb) * buf_size * sizeof(*pf->d_bnd_buf), cudaMemcpyHostToDevice));
  prof_stop(pr2);
  prof_start(pr3);
  fields_device_pack_yz<B, UNPACK>(pf, mb, me);
  cuda_sync_if_enabled();
  prof_stop(pr3);
}

// ======================================================================

EXTERN_C void
__fields_cuda_from_device_inside(fields_cuda_t *pf, struct cuda_fields_ctx *cf, int mb, int me)
{
  if (pf->im[0] == 2 * -pf->ib[0] + 1) {
    __fields_cuda_from_device_yz<2*BND>(pf, cf, mb, me);
  } else {
    unsigned int size = pf->im[0] * pf->im[1] * pf->im[2];
    check(cudaMemcpy(cf->arr,
		     pf->d_flds + mb * size,
		     (me - mb) * size * sizeof(float),
		     cudaMemcpyDeviceToHost));
  }
}

EXTERN_C void
__fields_cuda_to_device_outside(fields_cuda_t *pf, struct cuda_fields_ctx *cf, int mb, int me)
{
  if (pf->im[0] == 2 * -pf->ib[0] + 1) {
    __fields_cuda_to_device_yz<BND>(pf, cf, mb, me);
  } else {
    unsigned int size = pf->im[0] * pf->im[1] * pf->im[2];
    check(cudaMemcpy(pf->d_flds + mb * size,
		     cf->arr,
		     (me - mb) * size * sizeof(float),
		     cudaMemcpyHostToDevice));
  }
}

EXTERN_C void
__fields_cuda_to_device_inside(fields_cuda_t *pf, struct cuda_fields_ctx *cf, int mb, int me)
{
  if (pf->im[0] == 2 * -pf->ib[0] + 1) {
    __fields_cuda_to_device_yz<2*BND>(pf, cf, mb, me);
  } else {
    unsigned int size = pf->im[0] * pf->im[1] * pf->im[2];
    check(cudaMemcpy(pf->d_flds + mb * size,
		     cf->arr,
		     (me - mb) * size * sizeof(float),
		     cudaMemcpyHostToDevice));
  }
}
