
#include <psc_cuda.h>
#include "cuda_sort2.h"

#include <thrust/scan.h>
#include <thrust/device_vector.h>

#define PFX(x) xchg_##x
#include "constants.c"

// FIXME const mem for dims?
// FIXME probably should do our own loop rather than use blockIdx

__global__ static void
exchange_particles(int n_part, particles_cuda_dev_t d_part,
		   int ldimsx, int ldimsy, int ldimsz)
{
  int ldims[3] = { ldimsx, ldimsy, ldimsz };
  int xm[3];

  for (int d = 0; d < 3; d++) {
    xm[d] = ldims[d] / d_consts.dxi[d];
  }

  int i = threadIdx.x + THREADS_PER_BLOCK * blockIdx.x;
  if (i < n_part) {
    particle_cuda_real_t xi[3] = {
      d_part.xi4[i].x * d_consts.dxi[0],
      d_part.xi4[i].y * d_consts.dxi[1],
      d_part.xi4[i].z * d_consts.dxi[2] };
    int pos[3];
    for (int d = 0; d < 3; d++) {
      pos[d] = cuda_fint(xi[d]);
    }
    if (pos[1] < 0) {
      d_part.xi4[i].y += xm[1];
      if (d_part.xi4[i].y >= xm[1])
	d_part.xi4[i].y = 0.f;
    }
    if (pos[2] < 0) {
      d_part.xi4[i].z += xm[2];
      if (d_part.xi4[i].z >= xm[2])
	d_part.xi4[i].z = 0.f;
    }
    if (pos[1] >= ldims[1]) {
      d_part.xi4[i].y -= xm[1];
    }
    if (pos[2] >= ldims[2]) {
      d_part.xi4[i].z -= xm[2];
    }
  }
}

EXTERN_C void
cuda_exchange_particles(int p, particles_cuda_t *pp)
{
  struct psc_patch *patch = &ppsc->patch[p];

  fields_cuda_t pf_dummy;
  xchg_set_constants(pp, &pf_dummy);

  int dimBlock[2] = { THREADS_PER_BLOCK, 1 };
  int dimGrid[2]  = { (pp->n_part + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, 1 };
  RUN_KERNEL(dimGrid, dimBlock,
	     exchange_particles, (pp->n_part, pp->d_part,
				  patch->ldims[0], patch->ldims[1], patch->ldims[2]));
}

EXTERN_C void
cuda_alloc_block_indices(particles_cuda_t *pp, unsigned int **d_bidx)
{
  check(cudaMalloc((void **) d_bidx, pp->n_alloced * sizeof(**d_bidx)));
}

EXTERN_C void
cuda_free_block_indices(unsigned int *d_bidx)
{
  check(cudaFree(d_bidx));
}

EXTERN_C void
cuda_copy_bidx_from_dev(particles_cuda_t *pp, unsigned int *h_bidx, unsigned int *d_bidx)
{
  check(cudaMemcpy(h_bidx, d_bidx, pp->n_part * sizeof(*h_bidx),
		   cudaMemcpyDeviceToHost));
}

EXTERN_C void
cuda_copy_bidx_to_dev(particles_cuda_t *pp, unsigned int *d_bidx, unsigned int *h_bidx)
{
  check(cudaMemcpy(d_bidx, h_bidx, pp->n_part * sizeof(*d_bidx),
		   cudaMemcpyHostToDevice));
}

// ======================================================================
// cuda_find_block_indices

__global__ static void
find_block_indices(int n_part, particles_cuda_dev_t d_part, unsigned int *d_bidx,
		   int dimy, float b_dyi, float b_dzi, int b_my, int b_mz)
{
  int i = threadIdx.x + THREADS_PER_BLOCK * blockIdx.x;
  if (i < n_part) {
    float4 xi4 = d_part.xi4[i];
    unsigned int block_pos_y = cuda_fint(xi4.y * b_dyi);
    unsigned int block_pos_z = cuda_fint(xi4.z * b_dzi);

    int block_idx = block_pos_z * b_my + block_pos_y;
    d_bidx[i] = block_idx;
  }
}

EXTERN_C void
cuda_find_block_indices(particles_cuda_t *pp, unsigned int *d_bidx)
{
  int dimBlock[2] = { THREADS_PER_BLOCK, 1 };
  int dimGrid[2]  = { (pp->n_part + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, 1 };
  RUN_KERNEL(dimGrid, dimBlock,
	     find_block_indices, (pp->n_part, pp->d_part, d_bidx,
				  pp->map.dims[1], pp->b_dxi[1], pp->b_dxi[2],
				  pp->b_mx[1], pp->b_mx[2]));
}

// ======================================================================
// cuda_find_block_indices_ids

__global__ static void
find_block_indices_ids(int n_part, particles_cuda_dev_t d_part, unsigned int *d_bidx,
		       unsigned int *d_ids, int dimy, float b_dyi, float b_dzi, int b_my, int b_mz)
{
  int i = threadIdx.x + THREADS_PER_BLOCK * blockIdx.x;
  if (i < n_part) {
    float4 xi4 = d_part.xi4[i];
    unsigned int block_pos_y = cuda_fint(xi4.y * b_dyi);
    unsigned int block_pos_z = cuda_fint(xi4.z * b_dzi);

    int block_idx = block_pos_z * b_my + block_pos_y;
    d_bidx[i] = block_idx;
    d_ids[i] = i;
  }
}

EXTERN_C void
cuda_find_block_indices_ids(particles_cuda_t *pp, unsigned int *d_bidx,
			    unsigned int *d_ids)
{
  int dimBlock[2] = { THREADS_PER_BLOCK, 1 };
  int dimGrid[2]  = { (pp->n_part + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, 1 };
  RUN_KERNEL(dimGrid, dimBlock,
	     find_block_indices_ids, (pp->n_part, pp->d_part, d_bidx, d_ids,
				      pp->map.dims[1], pp->b_dxi[1], pp->b_dxi[2],
				      pp->b_mx[1], pp->b_mx[2]));
}

// ======================================================================
// cuda_find_block_indices_2
//
// like cuda_find_block_indices, but handles out-of-bound
// particles

__global__ static void
find_block_indices_2(int n_part, particles_cuda_dev_t d_part, unsigned int *d_bidx,
		     int dimy, float b_dyi, float b_dzi,
		     int b_my, int b_mz, int start)
{
  int i = threadIdx.x + THREADS_PER_BLOCK * blockIdx.x + start;
  if (i < n_part) {
    float4 xi4 = d_part.xi4[i];
    unsigned int block_pos_y = cuda_fint(xi4.y * b_dyi);
    unsigned int block_pos_z = cuda_fint(xi4.z * b_dzi);

    int block_idx;
    if (block_pos_y >= b_my || block_pos_z >= b_mz) {
      block_idx = b_my * b_mz;
    } else {
      block_idx = block_pos_z * b_my + block_pos_y;
    }
    d_bidx[i] = block_idx;
  }
}

EXTERN_C void
cuda_find_block_indices_2(particles_cuda_t *pp, unsigned int *d_bidx,
			  int start)
{
  int dimBlock[2] = { THREADS_PER_BLOCK, 1 };
  int dimGrid[2]  = { ((pp->n_part - start) + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, 1 };
  RUN_KERNEL(dimGrid, dimBlock,
	     find_block_indices_2, (pp->n_part, pp->d_part, d_bidx,
				    pp->map.dims[1], pp->b_dxi[1], pp->b_dxi[2],
				    pp->b_mx[1], pp->b_mx[2], start));
}

EXTERN_C void
_cuda_find_block_indices_2(particles_cuda_t *pp, unsigned int *d_bidx,
			   int start)
{
  float4 *xi4 = new float4[pp->n_part];
  float4 *pxi4 = new float4[pp->n_part];
  unsigned int *bidx = new unsigned int[pp->n_part];
  __particles_cuda_from_device(pp, xi4, pxi4);
  cuda_copy_bidx_from_dev(pp, bidx, d_bidx);

  float b_dyi = pp->b_dxi[1], b_dzi = pp->b_dxi[2];
  int b_my = pp->b_mx[1], b_mz = pp->b_mx[2];
  for (int i = start; i < pp->n_part; i++) {
    unsigned int block_pos_y = cuda_fint(xi4[i].y * b_dyi);
    unsigned int block_pos_z = cuda_fint(xi4[i].z * b_dzi);

    int block_idx;
    if (block_pos_y >= b_my || block_pos_z >= b_mz) {
      block_idx = pp->nr_blocks;
    } else {
      block_idx = block_pos_z * b_my + block_pos_y;
    }
    bidx[i] = block_idx;
  }
  
  cuda_copy_bidx_to_dev(pp, d_bidx, bidx);
  delete[] xi4;
  delete[] pxi4;
  delete[] bidx;
}

// ======================================================================
// cuda_find_block_indices_3

EXTERN_C void
cuda_find_block_indices_3(particles_cuda_t *pp, unsigned int *d_bidx,
			  unsigned int *d_alt_bidx,
			  int start, unsigned int *bn_idx, unsigned int *bn_off)
{
  // for consistency, use same block indices that we counted earlier
  check(cudaMemcpy(d_bidx + start, bn_idx, (pp->n_part - start) * sizeof(*d_bidx),
		   cudaMemcpyHostToDevice));
  // abuse of alt_bidx!!! FIXME
  check(cudaMemcpy(d_alt_bidx + start, bn_off, (pp->n_part - start) * sizeof(*d_bidx),
		   cudaMemcpyHostToDevice));
}

// ======================================================================
// reorder_send_buf

__global__ static void
reorder_send_buf(int n_part, particles_cuda_dev_t d_part, unsigned int *d_bidx,
		 unsigned int *d_sums, unsigned int nr_blocks)
{
  int i = threadIdx.x + THREADS_PER_BLOCK * blockIdx.x;
  if (i < n_part) {
    if (d_bidx[i] == nr_blocks) {
      int j = d_sums[i] + n_part;
      d_part.xi4[j] = d_part.xi4[i];
      d_part.pxi4[j] = d_part.pxi4[i];
    }
  }
}

EXTERN_C void
cuda_reorder_send_buf(int p, particles_cuda_t *pp, 
		      unsigned int *d_bidx, unsigned int *d_sums, int n_send)
{
  assert(pp->n_part + n_send <= pp->n_alloced);

  // OPT: don't pass offset, get it in device code
  int dimBlock[2] = { THREADS_PER_BLOCK, 1 };
  int dimGrid[2]  = { (pp->n_part + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, 1 };
  RUN_KERNEL(dimGrid, dimBlock,
	     reorder_send_buf, (pp->n_part, pp->d_part, d_bidx, d_sums, pp->nr_blocks));
}

EXTERN_C void
_cuda_reorder_send_buf(int p, particles_cuda_t *pp, 
		       unsigned int *d_bidx, unsigned int *d_sums, int n_send)
{
  int n_part = pp->n_part;
  int n_total = n_part + n_send;
  assert(n_total <= pp->n_alloced);
  float4 *xi4 = new float4[n_total];
  float4 *pxi4 = new float4[n_total];
  unsigned int *bidx = new unsigned int[n_total];
  unsigned int *sums = new unsigned int[n_total];
  __particles_cuda_from_device(pp, xi4, pxi4);
  cuda_copy_bidx_from_dev(pp, bidx, d_bidx);
  cuda_copy_bidx_from_dev(pp, sums, d_sums);

  for (int i = 0; i < pp->n_part; i++) {
    if (bidx[i] == pp->nr_blocks) {
      int j = sums[i] + pp->n_part;
      xi4[j] = xi4[i];
      pxi4[j] = pxi4[i];
    }
  }

  pp->n_part = n_total;
  __particles_cuda_to_device(pp, xi4, pxi4, NULL, NULL, NULL);
  pp->n_part = n_part;
  delete[] xi4;
  delete[] pxi4;
  delete[] bidx;
  delete[] sums;
}

// ======================================================================
// reorder_and_offsets

__global__ static void
reorder_and_offsets(int n_part, particles_cuda_dev_t d_part, float4 *xi4, float4 *pxi4,
		    unsigned int *d_bidx, unsigned int *d_ids, int nr_blocks)
{
  int i = threadIdx.x + THREADS_PER_BLOCK * blockIdx.x;

  if (i > n_part)
    return;

  int block, prev_block;
  if (i < n_part) {
    xi4[i] = d_part.xi4[d_ids[i]];
    pxi4[i] = d_part.pxi4[d_ids[i]];
    
    block = d_bidx[i];
  } else if (i == n_part) { // needed if there is no particle in the last block
    block = nr_blocks;
  }

  // create offsets per block into particle array
  prev_block = -1;
  if (i > 0) {
    prev_block = d_bidx[i-1];
  }
  for (int b = prev_block + 1; b <= block; b++) {
    d_part.offsets[b] = i;
  }
}

EXTERN_C void
cuda_reorder_and_offsets(particles_cuda_t *pp, unsigned int *d_bidx,
			 unsigned int *d_ids)
{
  float4 *alt_xi4 = pp->d_part.alt_xi4;
  float4 *alt_pxi4 = pp->d_part.alt_pxi4;

  int dimBlock[2] = { THREADS_PER_BLOCK, 1 };
  int dimGrid[2]  = { (pp->n_part + 1 + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, 1 };
  RUN_KERNEL(dimGrid, dimBlock,
	     reorder_and_offsets, (pp->n_part, pp->d_part, alt_xi4, alt_pxi4,
				   d_bidx, d_ids, pp->nr_blocks));

  pp->d_part.alt_xi4 = pp->d_part.xi4;
  pp->d_part.alt_pxi4 = pp->d_part.pxi4;
  pp->d_part.xi4 = alt_xi4;
  pp->d_part.pxi4 = alt_pxi4;
}

void
_cuda_reorder_and_offsets(particles_cuda_t *pp, unsigned int *d_bidx,
			  unsigned int *d_ids)
{
  float4 *xi4 = new float4[pp->n_part];
  float4 *pxi4 = new float4[pp->n_part];
  float4 *alt_xi4 = new float4[pp->n_part];
  float4 *alt_pxi4 = new float4[pp->n_part];
  unsigned int *bidx = new unsigned int[pp->n_part];
  unsigned int *ids = new unsigned int[pp->n_part];
  int *offsets = new int[pp->nr_blocks + 2];

  __particles_cuda_from_device(pp, xi4, pxi4);
  cuda_copy_bidx_from_dev(pp, bidx, d_bidx);
  cuda_copy_bidx_from_dev(pp, ids, d_ids);

  for (int i = 0; i < pp->n_part; i++) {
    alt_xi4[i] = xi4[ids[i]];
    alt_pxi4[i] = pxi4[ids[i]];

    int block = bidx[i];
    int prev_block = (i > 0) ? (int) bidx[i-1] : -1;
    for (int b = prev_block + 1; b <= block; b++) {
      offsets[b] = i;
    }
  }
  int block = pp->nr_blocks + 1;
  int prev_block = bidx[pp->n_part - 1];
  for (int b = prev_block + 1; b <= block; b++) {
    offsets[b] = pp->n_part;
  }

  float4 *d_alt_xi4 = pp->d_part.alt_xi4;
  float4 *d_alt_pxi4 = pp->d_part.alt_pxi4;
  pp->d_part.alt_xi4 = pp->d_part.xi4;
  pp->d_part.alt_pxi4 = pp->d_part.pxi4;
  pp->d_part.xi4 = d_alt_xi4;
  pp->d_part.pxi4 = d_alt_pxi4;

  __particles_cuda_to_device(pp, alt_xi4, alt_pxi4, offsets, NULL, NULL);
  delete[] xi4;
  delete[] pxi4;
  delete[] alt_xi4;
  delete[] alt_pxi4;
  delete[] bidx;
  delete[] ids;
  delete[] offsets;
}

// ======================================================================
// cuda_reorder

__global__ static void
reorder(int n_part, particles_cuda_dev_t d_part, float4 *xi4, float4 *pxi4,
	unsigned int *d_ids)
{
  int i = threadIdx.x + THREADS_PER_BLOCK * blockIdx.x;

  if (i < n_part) {
    xi4[i] = d_part.xi4[d_ids[i]];
    pxi4[i] = d_part.pxi4[d_ids[i]];
  }
}

EXTERN_C void
cuda_reorder(particles_cuda_t *pp, unsigned int *d_ids)
{
  float4 *alt_xi4 = pp->d_part.alt_xi4;
  float4 *alt_pxi4 = pp->d_part.alt_pxi4;

  int dimBlock[2] = { THREADS_PER_BLOCK, 1 };
  int dimGrid[2]  = { (pp->n_part + 1 + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, 1 };
  RUN_KERNEL(dimGrid, dimBlock,
	     reorder, (pp->n_part, pp->d_part, alt_xi4, alt_pxi4, d_ids));

  pp->d_part.alt_xi4 = pp->d_part.xi4;
  pp->d_part.alt_pxi4 = pp->d_part.pxi4;
  pp->d_part.xi4 = alt_xi4;
  pp->d_part.pxi4 = alt_pxi4;
}

// ======================================================================
// cuda_exclusive_scan

EXTERN_C int
_cuda_exclusive_scan(int p, particles_cuda_t *pp,
		    unsigned int *d_vals, unsigned int *d_sums)
{
  unsigned int *vals = new unsigned int[pp->n_part];
  unsigned int *sums = new unsigned int[pp->n_part];
  cuda_copy_bidx_from_dev(pp, vals, d_vals);

  unsigned int sum = 0;
  for (int i = 0; i < pp->n_part; i++) {
    sums[i] = sum;
    sum += vals[i];
  }

  cuda_copy_bidx_to_dev(pp, d_sums, sums);
  delete[] sums;
  delete[] vals;
  return sum;
}

EXTERN_C int
cuda_exclusive_scan(int p, particles_cuda_t *pp, unsigned int *_d_vals, unsigned int *_d_sums)
{
  thrust::device_ptr<unsigned int> d_vals(_d_vals);
  thrust::device_ptr<unsigned int> d_sums(_d_sums);
  thrust::exclusive_scan(d_vals, d_vals + pp->n_part, d_sums);
  int sum = d_sums[pp->n_part - 1] + d_vals[pp->n_part - 1];
  return sum;
}

