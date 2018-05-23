
#ifndef FIELDS3D_HXX
#define FIELDS3D_HXX

#include "psc.h"

#include "grid.hxx"
#include "psc_fields.h"

#include <mrc_profile.h>

#include <type_traits>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <algorithm>
#include <unordered_map>
#include <typeindex>
#include <list>
#include <string>

template<bool AOS>
struct Layout
{
  using isAOS = std::integral_constant<bool, AOS>;
};

using LayoutAOS = Layout<true>;
using LayoutSOA = Layout<false>;

// ======================================================================
// fields3d

template<typename R, typename L=LayoutSOA>
struct fields3d {
  using real_t = R;
  using layout = L;

  fields3d(Int3 ib, Int3 im, int n_comps, real_t* data=nullptr)
    : ib_{ib}, im_{im},
      n_comps_{n_comps},
      data_{data}
  {
    if (!data_) {
      data_ = (real_t *) calloc(size(), sizeof(*data_));
    }
  }

  void dtor()
  {
    free(data_);
    data_ = NULL;
  }

  real_t  operator()(int m, int i, int j, int k) const { return data_[index(m, i, j, k)];  }
  real_t& operator()(int m, int i, int j, int k)       { return data_[index(m, i, j, k)];  }

  real_t* data() { return data_; }
  int index(int m, int i, int j, int k) const;
  int n_comps() const { return n_comps_; }
  int n_cells() const { return im_[0] * im_[1] * im_[2]; }
  int size()    const { return n_comps() * n_cells(); }
  Int3 ib()     const { return ib_; }
  Int3 im()     const { return im_; }

  void zero(int m)
  {
    memset(&(*this)(m, ib_[0], ib_[1], ib_[2]), 0, n_cells() * sizeof(real_t));
  }

  void zero(int mb, int me)
  {
    for (int m = mb; m < me; m++) {
      zero(m);
    }
  }

  void zero()
  {
    memset(data_, 0, sizeof(real_t) * size());
  }

  void set(int m, real_t val)
  {
    for (int k = ib_[2]; k < ib_[2] + im_[2]; k++) {
      for (int j = ib_[1]; j < ib_[1] + im_[1]; j++) {
	for (int i = ib_[0]; i < ib_[0] + im_[0]; i++) {
	  (*this)(m, i,j,k) = val;
	}
      }
    }
  }

  void scale(int m, real_t val)
  {
    for (int k = ib_[2]; k < ib_[2] + im_[2]; k++) {
      for (int j = ib_[1]; j < ib_[1] + im_[1]; j++) {
	for (int i = ib_[0]; i < ib_[0] + im_[0]; i++) {
	  (*this)(m, i,j,k) *= val;
	}
      }
    }
  }

  void copy_comp(int mto, const fields3d& from, int mfrom)
  {
    for (int k = ib_[2]; k < ib_[2] + im_[2]; k++) {
      for (int j = ib_[1]; j < ib_[1] + im_[1]; j++) {
	for (int i = ib_[0]; i < ib_[0] + im_[0]; i++) {
	  (*this)(mto, i,j,k) = from(mfrom, i,j,k);
	}
      }
    }
  }

  void axpy_comp(int m_y, real_t alpha, const fields3d& x, int m_x)
  {
    for (int k = ib_[2]; k < ib_[2] + im_[2]; k++) {
      for (int j = ib_[1]; j < ib_[1] + im_[1]; j++) {
	for (int i = ib_[0]; i < ib_[0] + im_[0]; i++) {
	  (*this)(m_y, i,j,k) += alpha * x(m_x, i,j,k);
	}
      }
    }
  }

  real_t max_comp(int m)
  {
    real_t rv = -std::numeric_limits<real_t>::max();
    for (int k = ib_[2]; k < ib_[2] + im_[2]; k++) {
      for (int j = ib_[1]; j < ib_[1] + im_[1]; j++) {
	for (int i = ib_[0]; i < ib_[0] + im_[0]; i++) {
	  rv = std::max(rv, (*this)(m, i,j,k));
	}
      }
    }
    return rv;
  }

  void dump()
  {
    for (int k = ib_[2]; k < ib_[2] + im_[2]; k++) {
      for (int j = ib_[1]; j < ib_[1] + im_[1]; j++) {
	for (int i = ib_[0]; i < ib_[0] + im_[0]; i++) {
	  for (int m = 0; m < n_comps_; m++) {
	    mprintf("dump: ijk %d:%d:%d m %d: %g\n", i, j, k, m, (*this)(m, i,j,k));
	  }
	}
      }
    }
  }

  real_t* data_;
  Int3 ib_, im_; //> lower bounds and length per direction
  int n_comps_; // # of components
};

template<typename R, typename L>
int fields3d<R, L>::index(int m, int i, int j, int k) const
{
#ifdef BOUNDS_CHECK
  assert(m >= 0 && m < n_comps_);
  assert(i >= ib_[0] && i < ib_[0] + im_[0]);
  assert(j >= ib_[1] && j < ib_[1] + im_[1]);
  assert(k >= ib_[2] && k < ib_[2] + im_[2]);
#endif

  if (L::isAOS::value) {
    return (((((k - ib_[2])) * im_[1] +
	      (j - ib_[1])) * im_[0] +
	     (i - ib_[0])) * n_comps_ + m);
  } else {
    return (((((m) * im_[2] +
	       (k - ib_[2])) * im_[1] +
	      (j - ib_[1])) * im_[0] +
	     (i - ib_[0])));
  }
}

// ======================================================================
// MfieldsBase

struct MfieldsBase
{
  using convert_func_t = void (*)(MfieldsBase&, MfieldsBase&, int, int);
  using Convert = std::unordered_map<std::type_index, convert_func_t>;
  
  struct fields_t { struct real_t {}; };
  
  MfieldsBase(const Grid_t& grid, int n_fields, Int3 ibn)
    : grid_(&grid),
      n_fields_(n_fields),
      ibn_(ibn)
  {
    instances.push_back(this);
  }

  virtual ~MfieldsBase()
  {
    instances.remove(this);
  }

  virtual void reset(const Grid_t& grid) { grid_ = &grid; }
  
  int n_patches() const { return grid_->n_patches(); }
  int n_comps() const { return n_fields_; }
  Int3 ibn() const { return ibn_; }

  virtual void zero_comp(int m) = 0;
  virtual void set_comp(int m, double val) = 0;
  virtual void scale_comp(int m, double val) = 0;
  virtual void axpy_comp(int m_y, double alpha, MfieldsBase& x, int m_x) = 0;
  virtual double max_comp(int m) = 0;
  virtual void write_as_mrc_fld(mrc_io *io, const std::string& name, const std::vector<std::string>& comp_names)
  {
    assert(0);
  }

  void zero()            { for (int m = 0; m < n_fields_; m++) zero_comp(m); }
  void scale(double val) { for (int m = 0; m < n_fields_; m++) scale_comp(m, val); }
  void axpy(double alpha, MfieldsBase& x)
  {
    for (int m = 0; m < n_fields_; m++) {
      axpy_comp(m, alpha, x, m);
    }
  }

  const Grid_t& grid() { return *grid_; }
  
  template<typename MF>
  MF& get_as(int mb, int me)
  {
    // If we're already the subtype, nothing to be done
    if (typeid(*this) == typeid(MF)) {
      return *dynamic_cast<MF*>(this);
    }
    
    static int pr;
    if (!pr) {
      pr = prof_register("Mfields_get_as", 1., 0, 0);
    }
    prof_start(pr);

    // mprintf("get_as %s (%s) %d %d\n", type, psc_mfields_type(mflds_base), mb, me);
    
    auto& mflds = *new MF{grid(), n_comps(), ibn()};
    
    MfieldsBase::convert(*this, mflds, mb, me);

    prof_stop(pr);
    return mflds;
  }

  template<typename MF>
  void put_as(MF& mflds, int mb, int me)
  {
    // If we're already the subtype, nothing to be done
    if (typeid(*this) == typeid(mflds)) {
      return;
    }
    
    static int pr;
    if (!pr) {
      pr = prof_register("Mfields_put_as", 1., 0, 0);
    }
    prof_start(pr);
    
    MfieldsBase::convert(mflds, *this, mb, me);
    delete &mflds;
    
    prof_stop(pr);
  }

  virtual const Convert& convert_to() { static const Convert convert_to_; return convert_to_; }
  virtual const Convert& convert_from() { static const Convert convert_from_; return convert_from_; }
  static void convert(MfieldsBase& mf_from, MfieldsBase& mf_to, int mb, int me);

  static std::list<MfieldsBase*> instances;
  
protected:
  int n_fields_;
  const Grid_t* grid_;
  Int3 ibn_;
public:
  bool inited = true; // FIXME hack to avoid dtor call when not yet constructed
};

// ======================================================================
// Mfields

template<typename F>
struct Mfields : MfieldsBase
{
  using fields_t = F;
  using real_t = typename fields_t::real_t;

  Mfields(const Grid_t& grid, int n_fields, Int3 ibn)
    : MfieldsBase(grid, n_fields, ibn)
  {
    unsigned int size = 1;
    for (int d = 0; d < 3; d++) {
      ib[d] = -ibn[d];
      im[d] = grid_->ldims[d] + 2 * ibn[d];
      size *= im[d];
    }

    data.reserve(n_patches());
    for (int p = 0; p < n_patches(); p++) {
      data.emplace_back(new real_t[n_fields * size]{});
    }
  }

  virtual void reset(const Grid_t& grid) override
  {
    MfieldsBase::reset(grid);
    data.clear();

    unsigned int size = 1;
    for (int d = 0; d < 3; d++) {
      size *= im[d];
    }

    data.reserve(n_patches());
    for (int p = 0; p < n_patches(); p++) {
      data.emplace_back(new real_t[n_comps() * size]);
    }
  }
  
  fields_t operator[](int p)
  {
    return fields_t(ib, im, n_fields_, data[p].get());
  }

  void zero_comp(int m) override
  {
    for (int p = 0; p < n_patches(); p++) {
      (*this)[p].zero(m);
    }
  }

  void set_comp(int m, double val) override
  {
    for (int p = 0; p < n_patches(); p++) {
      (*this)[p].set(m, val);
    }
  }
  
  void scale_comp(int m, double val) override
  {
    for (int p = 0; p < n_patches(); p++) {
      (*this)[p].scale(m, val);
    }
  }

  void copy_comp(int mto, Mfields& from, int mfrom)
  {
    for (int p = 0; p < n_patches(); p++) {
      (*this)[p].copy_comp(mto, from[p], mfrom);
    }
  }
  
  void axpy_comp(int m_y, double alpha, MfieldsBase& x_base, int m_x) override
  {
    // FIXME? dynamic_cast would actually be more appropriate
    Mfields& x = static_cast<Mfields&>(x_base);
    for (int p = 0; p < n_patches(); p++) {
      (*this)[p].axpy_comp(m_y, alpha, x[p], m_x);
    }
  }

  double max_comp(int m) override
  {
    double rv = -std::numeric_limits<double>::max();
    for (int p = 0; p < n_patches(); p++) {
      rv = std::max(rv, double((*this)[p].max_comp(m)));
    }
    return rv;
  }

  void write_as_mrc_fld(mrc_io *io, const std::string& name, const std::vector<std::string>& comp_names) override
  {
    mrc_fld* fld = mrc_domain_m3_create(ppsc->mrc_domain_);
    mrc_fld_set_name(fld, name.c_str());
    mrc_fld_set_param_int(fld, "nr_ghosts", 0);
    mrc_fld_set_param_int(fld, "nr_comps", n_comps());
    mrc_fld_setup(fld);
    assert(comp_names.size() == n_comps());
    for (int m = 0; m < n_comps(); m++) {
      mrc_fld_set_comp_name(fld, m, comp_names[m].c_str());
    }

    for (int p = 0; p < n_patches(); p++) {
      mrc_fld_patch *m3p = mrc_fld_patch_get(fld, p);
      mrc_fld_foreach(fld, i,j,k, 0,0) {
	for (int m = 0; m < n_comps(); m++) {
	  MRC_M3(m3p ,m , i,j,k) = (*this)[p](m, i,j,k);
	}
      } mrc_fld_foreach_end;
      mrc_fld_patch_put(fld);
    }
  
    mrc_fld_write(fld, io);
    mrc_fld_destroy(fld);
  }

  static const Convert convert_to_, convert_from_;
  const Convert& convert_to() override { return convert_to_; }
  const Convert& convert_from() override { return convert_from_; }

  std::vector<std::unique_ptr<real_t[]>> data;
  int ib[3]; //> lower left corner for each patch (incl. ghostpoints)
  int im[3]; //> extent for each patch (incl. ghostpoints)
};

// ======================================================================
// PscMfields

template<typename S> struct PscMfields;
using PscMfieldsBase = PscMfields<MfieldsBase>;

template<typename S>
struct PscMfields
{
  using Self = PscMfields<S>;
  using sub_t = S;
  using fields_t = typename sub_t::fields_t;
  using real_t = typename fields_t::real_t;

  static_assert(std::is_convertible<sub_t*, MfieldsBase*>::value,
		"sub classes used in mfields_t must derive from psc_mfields_base");

  static Self create(MPI_Comm comm, const Grid_t& grid, int n_comps, Int3 ibn);
  
  PscMfields(struct psc_mfields *mflds)
    : mflds_(mflds)
  {
    if (mflds != nullptr) {
      assert(dynamic_cast<sub_t*>(mrc_to_subobj(mflds, MfieldsBase)));
    }
  }

  unsigned int n_fields() const { return mflds_->nr_fields; }

  fields_t operator[](int p)
  {
    return (*sub())[p];
  }

  struct psc_mfields *mflds() { return mflds_; }
  
  sub_t* operator->() { return sub(); }
  sub_t* sub() { return mrc_to_subobj(mflds_, sub_t); }
  
private:
  struct psc_mfields *mflds_;
};

inline PscMfieldsBase PscMfieldsCreate(MPI_Comm comm, const Grid_t& grid, int n_comps,
				       Int3 ibn, const char* type)
{
  psc_mfields *mflds = psc_mfields_create(comm);
  psc_mfields_set_type(mflds, type);
  psc_mfields_set_param_int(mflds, "nr_fields", n_comps);
  psc_mfields_set_param_int3(mflds, "ibn", ibn);
  mflds->grid = &grid;
  psc_mfields_setup(mflds);
  return mflds;
}

template<typename S>
PscMfields<S> PscMfields<S>::create(MPI_Comm comm, const Grid_t& grid, int n_comps, Int3 ibn)
{
  return Self{PscMfieldsCreate(comm, grid, n_comps, ibn, Mfields_traits<S>::name).mflds()};
}
  
// ======================================================================
// MfieldsWrapper

template<typename Mfields>
class MfieldsWrapper
{
public:
  const static size_t size = sizeof(Mfields);

  constexpr static const char* name = Mfields_traits<Mfields>::name;
  
  static void setup(struct psc_mfields* _mflds)
  {
    psc_mfields_setup_super(_mflds);
    
    new(_mflds->obj.subctx) Mfields{*_mflds->grid, _mflds->nr_fields, _mflds->ibn};
    _mflds->grid = nullptr; // to prevent subsequent use, there's Mfields::grid() instead
  }

  static void destroy(struct psc_mfields* _mflds)
  {
    if (!mrc_to_subobj(_mflds, MfieldsBase)->inited) return; // FIXME
    PscMfields<Mfields> mflds(_mflds);
    mflds->~Mfields();
  }
};

#endif
