
#include "vpic_config.h"
#include "vpic_iface.h"

#include <cassert>
#include <mrc_common.h>

// ----------------------------------------------------------------------
// C wrappers

Simulation* Simulation_create()
{
  mpi_printf(psc_comm_world, "*** Initializing\n" );
  return new Simulation();
}

void Simulation_delete(Simulation* sim)
{
  delete sim;
}

void Simulation_setup_grid(Simulation* sim, double dx[3], double dt,
			   double cvac, double eps0)
{
  sim->setup_grid(dx, dt, cvac, eps0);
}

void Simulation_define_periodic_grid(Simulation* sim, double xl[3],
				     double xh[3], const int gdims[3], const int np[3])
{
  sim->define_periodic_grid(xl, xh, gdims, np);
}

void Simulation_set_domain_field_bc(Simulation* sim, int boundary, int bc)
{
  sim->set_domain_field_bc(boundary, bc);
}

void Simulation_set_domain_particle_bc(Simulation* sim, int boundary, int bc)
{
  sim->set_domain_particle_bc(boundary, bc);
}

struct material *Simulation_define_material(Simulation* sim, const char *name,
					    double eps, double mu,
					    double sigma, double zeta)
{
  return reinterpret_cast<struct material*>(sim->define_material(name, eps, mu, sigma, zeta));
}

void Simulation_define_field_array(Simulation* sim, double damp)
{
  sim->define_field_array(damp);
}

struct species * Simulation_define_species(Simulation* sim, const char *name, double q, double m,
					   double max_local_np, double max_local_nm,
					   double sort_interval, double sort_out_of_place)
{
  return reinterpret_cast<struct species*>(sim->define_species(name, q, m, max_local_np, max_local_nm,
							       sort_interval, sort_out_of_place));
}

Particles * Simulation_get_particles(Simulation *sim)
{
  return &sim->particles_;
}

