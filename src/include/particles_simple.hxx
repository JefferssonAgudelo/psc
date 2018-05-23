
#pragma once

#include "particles.hxx"

// ======================================================================
// Particle positions in cell / patch

// Particle positions are stored as patch-relative positions, however,
// it is required to know the exact cell a particle is in in a number of places:
// - for performance sorting particles
// - for keeping particles sorted in, e.g., the CUDA particle pusher
// - for finding the appropriate EM fields to interpolate
// - for correctly depositing currents
// - for collisions
//
// The goal here is to establish rules / invariants of the position of
// particles to where (in which patch) they are stored and how to
// recover the cell they are in.
//
// To complicate things, there are currently two aspects to this: Cell
// position and block position, where the former refers to the
// computational mesh that E, B and J live on, whereas a block refers
// to a fixed-size super-cell (e.g., 4x4x4 cells), motivated by
// performance considerations. It is currently not necessarily clear
// that the calculated block indices and cell indices satisfy the
// anticipated relation (bpos[d] = cpos[d] / bs[d]) because of potential
// finite precision arithmetic
//
// Rules / invariants:
//
// for all particles in a given patch,
// (1) the cell position cpos
//     calculated in a given dimension d will satisfy 0 <= cpos < ldims[d]
// (2) the patch relative position xi satisfies
//     0 <= xi <= xm[d] = ldims[d] * dx[d]
//     with the equality at the upper limit only being allowed at a right/top
//     non-periodic boundary
//
// These invariants will be temporarily violated after the particle push, but will
// be restored by the bnd exchange.
//
// Tricky issues to deal with:
// - (1) and (2) should be closely related, but finite precision
//   arithmetic can cause surprises.
//
//   E.g.: dx = 1 ldims = 100. Particle ends up at position -1e-7. It
//   gets sent to the left, where it's new position will be -1e-7 +
//   100., which is actually = 100. (in single precision), meaning that
//   particle violates (1) and (2) in its new patch.
//
// - Calculating cpos correctly when legally xi == ldims[d] * xi[d] at a right boundary
//
// TODO:
// - have cell index be the primary quantity computed, always, and find
//   block index from that
// - boundary exchange should be based on cell, not block index
//   (though if the two indices are always consistent, it becomes a non-issue)

// ======================================================================
// ParticleIndexer

template<class R>
struct ParticleIndexer
{
  using real_t = R;
  using Real3 = Vec3<real_t>;

  ParticleIndexer(const Grid_t& grid)
    : dxi_(Real3(1.) / Real3(grid.domain.dx)),
      ldims_(grid.ldims)
  {
    n_cells_ = ldims_[0] * ldims_[1] * ldims_[2];
  }

  int cellPosition(real_t x, int d) const
  {
    return fint(x * dxi_[d]);
  }

  Int3 cellPosition(const real_t* pos) const
  {
    Int3 idx;
    for (int d = 0; d < 3; d++) {
      idx[d] = cellPosition(pos[d], d);
    }
    return idx;
  }

  int cellIndex(const Int3& cpos) const
  {
    if (uint(cpos[0]) >= ldims_[0] ||
	uint(cpos[1]) >= ldims_[1] ||
	uint(cpos[2]) >= ldims_[2]) {
      return -1;
    }
    
    return (cpos[2] * ldims_[1] + cpos[1]) * ldims_[0] + cpos[0];
  }

  int cellIndex(const real_t* pos) const
  {
    Int3 cpos = cellPosition(pos);
    return cellIndex(cpos);
  }

  int validCellIndex(const real_t* pos) const
  {
    Int3 cpos = cellPosition(pos);
    for (int d = 0; d < 3; d++) {
      if (uint(cpos[d]) >= ldims_[d]) {
	printf("validCellIndex: cpos[%d] = %d ldims_[%d] = %d // pos[%d] = %g pos[%d]*dxi_[%d] = %g\n",
	       d, cpos[d], d, ldims_[d], d, pos[d], d, d, pos[d] * dxi_[d]);
	assert(0);
      }
    }
    int cidx = cellIndex(cpos);
    assert(cidx >= 0);
    return cidx;
  }

  void checkInPatchMod(real_t* xi) const
  {
    for (int d = 0; d < 3; d++) {
      int pos = cellPosition(xi[d], d);
      if (pos < 0 || pos >= ldims_[d]) {
	printf("checkInPatchMod xi %g %g %g\n", xi[0], xi[1], xi[2]);
	printf("checkInPatchMod d %d xi %g pos %d // %d\n",
	       d, xi[d], pos, ldims_[d]);
	if (pos < 0) {
	  xi[d] = 0.f;
	} else {
	  xi[d] *= (1. - 1e-6);
	}
	pos = cellPosition(xi[d], d);
      }
      assert(pos >= 0 && pos < ldims_[d]);
    }
  }

  const Int3& ldims() const { return ldims_; }
  
  //private:
  Real3 dxi_;
  Int3 ldims_;
  uint n_cells_;
};

// ======================================================================
// psc_particle

template<class R>
struct psc_particle
{
  using real_t = R;

  real_t xi, yi, zi;
  real_t qni_wni_;
  real_t pxi, pyi, pzi;
  int kind_;

  int kind() const { return kind_; }

  // FIXME, grid is always double precision, so this will switch precision
  // where not desired. should use same info stored in mprts at right precision
  real_t qni(const Grid_t& grid) const { return grid.kinds[kind_].q; }
  real_t mni(const Grid_t& grid) const { return grid.kinds[kind_].m; }
  real_t wni(const Grid_t& grid) const { return qni_wni_ / qni(grid); }
  real_t qni_wni(const Grid_t& grid) const { return qni_wni_; }
};

// ======================================================================
// mparticles_patch_base

template<typename P>
struct Mparticles;

template<typename P>
struct mparticles_patch_base
{
  using particle_t = P;
  using real_t = typename particle_t::real_t;
  using Real3 = Vec3<real_t>;
  using buf_t = std::vector<particle_t>;
  using iterator = typename buf_t::iterator;
  using const_iterator = typename buf_t::const_iterator;
  
  // FIXME, I would like to delete the copy ctor because I don't
  // want to copy patch_t by mistake, but that doesn't play well with
  // putting the patches into std::vector
  // mparticles_patch_base(const mparticles_patch_base&) = delete;

  mparticles_patch_base(Mparticles<P>* mprts, int p)
    : pi_(mprts->grid()),
      mprts_(mprts),
      p_(p),
      grid_(&mprts->grid())
  {}

  particle_t& operator[](int n) { return buf[n]; }
  const_iterator begin() const { return buf.begin(); }
  iterator begin() { return buf.begin(); }
  const_iterator end() const { return buf.end(); }
  iterator end() { return buf.end(); }
  unsigned int size() const { return buf.size(); }
  void reserve(unsigned int new_capacity) { buf.reserve(new_capacity); }

  void push_back(particle_t& prt) // FIXME, should particle_t be const?
  {
    checkInPatchMod(prt);
    validCellIndex(prt);
    buf.push_back(prt);
  }

  void resize(unsigned int new_size)
  {
    assert(new_size <= buf.capacity());
    buf.resize(new_size);
  }

  void check() const
  {
    for (auto& prt : buf) {
      validCellIndex(prt);
    }
  }

  // ParticleIndexer functionality
  int cellPosition(real_t xi, int d) const { return pi_.cellPosition(xi, d); }
  int validCellIndex(const particle_t& prt) const { return pi_.validCellIndex(&prt.xi); }

  void checkInPatchMod(particle_t& prt) const { return pi_.checkInPatchMod(&prt.xi); }
  const ParticleIndexer<real_t>& particleIndexer() const { return pi_; }
    
  real_t prt_qni(const particle_t& prt) const { return prt.qni(*grid_); }
  real_t prt_mni(const particle_t& prt) const { return prt.mni(*grid_); }
  real_t prt_wni(const particle_t& prt) const { return prt.wni(*grid_); }
  real_t prt_qni_wni(const particle_t& prt) const { return prt.qni_wni(*grid_); }

  const Grid_t& grid() { return *grid_; }

  buf_t buf;
  ParticleIndexer<real_t> pi_;

private:
  Mparticles<P>* mprts_;
  int p_;
  const Grid_t* grid_;
};

template<typename P>
struct mparticles_patch : mparticles_patch_base<P> {
  using Base = mparticles_patch_base<P>;
  
  using Base::Base;
};

// ======================================================================
// Mparticles

template<typename P>
struct Mparticles : MparticlesBase
{
  using Self = Mparticles<P>;
  using particle_t = P;
  using particle_real_t = typename particle_t::real_t; // FIXME, should go away
  using real_t = particle_real_t;
  using patch_t = mparticles_patch<particle_t>;
  using buf_t = typename patch_t::buf_t;

  Mparticles(const Grid_t& grid)
    : MparticlesBase(grid)
  {
    patches_.reserve(grid.n_patches());
    for (int p = 0; p < grid.n_patches(); p++) {
      patches_.emplace_back(this, p);
    }
  }

  void reset(const Grid_t& grid) override
  {
    MparticlesBase::reset(grid);
    patches_.clear();
    patches_.reserve(grid.n_patches());
    for (int p = 0; p < grid.n_patches(); p++) {
      patches_.emplace_back(this, p);
    }
  }

  
  const patch_t& operator[](int p) const { return patches_[p]; }
  patch_t&       operator[](int p)       { return patches_[p]; }

  void reserve_all(const uint *n_prts_by_patch) override
  {
    for (int p = 0; p < patches_.size(); p++) {
      patches_[p].reserve(n_prts_by_patch[p]);
    }
  }

  void resize_all(const uint *n_prts_by_patch) override
  {
    for (int p = 0; p < patches_.size(); p++) {
      patches_[p].resize(n_prts_by_patch[p]);
    }
  }

  void get_size_all(uint *n_prts_by_patch) const override
  {
    for (int p = 0; p < patches_.size(); p++) {
      n_prts_by_patch[p] = patches_[p].size();
    }
  }

  int get_n_prts() const override
  {
    int n_prts = 0;
    for (auto const& patch : patches_) {
      n_prts += patch.size();
    }
    return n_prts;
  }
  
  void check() const
  {
    for (auto& patch: patches_) {
      patch.check();
    }
  }

  void inject(int p, const psc_particle_inject& new_prt) override
  {
    int kind = new_prt.kind;

    const Grid_t::Patch& patch = grid_->patches[p];
    for (int d = 0; d < 3; d++) {
      assert(new_prt.x[d] >= patch.xb[d]);
      assert(new_prt.x[d] <= patch.xe[d]);
    }
    
    particle_t prt;
    prt.xi      = new_prt.x[0] - patch.xb[0];
    prt.yi      = new_prt.x[1] - patch.xb[1];
    prt.zi      = new_prt.x[2] - patch.xb[2];
    prt.pxi     = new_prt.u[0];
    prt.pyi     = new_prt.u[1];
    prt.pzi     = new_prt.u[2];
    prt.qni_wni_ = new_prt.w * grid_->kinds[kind].q;
    prt.kind_   = kind;
    
    (*this)[p].push_back(prt);
  }
  
  void inject_reweight(int p, const psc_particle_inject& new_prt) override
  {
    int kind = new_prt.kind;

    const Grid_t::Patch& patch = grid_->patches[p];
    for (int d = 0; d < 3; d++) {
      assert(new_prt.x[d] >= patch.xb[d]);
      assert(new_prt.x[d] <= patch.xe[d]);
    }
    
    float dVi = 1.f / (grid_->domain.dx[0] * grid_->domain.dx[1] * grid_->domain.dx[2]);
    
    particle_t prt;
    prt.xi      = new_prt.x[0] - patch.xb[0];
    prt.yi      = new_prt.x[1] - patch.xb[1];
    prt.zi      = new_prt.x[2] - patch.xb[2];
    prt.pxi     = new_prt.u[0];
    prt.pyi     = new_prt.u[1];
    prt.pzi     = new_prt.u[2];
    prt.qni_wni_ = new_prt.w * grid_->kinds[kind].q * dVi;
    prt.kind_   = kind;
    
    (*this)[p].push_back(prt);
  }

  void dump(const std::string& filename)
  {
    FILE* file = fopen(filename.c_str(), "w");
    assert(file);

    for (int p = 0; p < n_patches(); p++) {
      auto& prts = (*this)[p];
      fprintf(file, "mparticles_dump: p%d n_prts = %d\n", p, prts.size());
      for (int n = 0; n < prts.size(); n++) {
	auto& prt = prts[n];
	fprintf(file, "mparticles_dump: [%d] %g %g %g // %d // %g %g %g // %g\n",
		n, prt.xi, prt.yi, prt.zi, prt.kind_,
		prt.pxi, prt.pyi, prt.pzi, prt.qni_wni_);
      }
    }
    fclose(file);
  }
  
  particle_real_t prt_qni(const particle_t& prt) const { return prt.qni(*grid_); }
  particle_real_t prt_mni(const particle_t& prt) const { return prt.mni(*grid_); }
  particle_real_t prt_wni(const particle_t& prt) const { return prt.wni(*grid_); }
  particle_real_t prt_qni_wni(const particle_t& prt) const { return prt.qni_wni(*grid_); }

  static const Convert convert_to_, convert_from_;
  const Convert& convert_to() override { return convert_to_; }
  const Convert& convert_from() override { return convert_from_; }

private:
  std::vector<patch_t> patches_;
};

