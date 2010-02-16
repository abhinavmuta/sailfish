<%!
    from sailfish import sym
%>

#define BLOCK_SIZE ${block_size}
#define DIST_SIZE ${dist_size}
#define GEO_FLUID ${geo_fluid}
#define GEO_BCV ${geo_bcv}
#define GEO_BCP ${geo_bcp}

#define DT 1.0f

%if 'gravity' in context.keys():
	${const_var} float gravity = ${gravity}f;
%endif

${const_var} float tau = ${tau}f;		// relaxation time
${const_var} float visc = ${visc}f;		// viscosity
${const_var} float geo_params[${num_params+1}] = {
% for param in geo_params:
	${param}f,
% endfor
0};		// geometry parameters

<%namespace file="opencl_compat.mako" import="*" name="opencl_compat"/>
<%namespace file="kernel_common.mako" import="*"/>
<%namespace file="tracers.mako" import="*"/>
<%namespace file="boundary.mako" import="*" name="boundary"/>
<%namespace file="relaxation.mako" import="*" name="relaxation"/>
<%namespace file="propagation.mako" import="*"/>

${opencl_compat.body()}
<%include file="geo_helpers.mako"/>
${boundary.body()}
${relaxation.body()}

<%include file="tracers.mako"/>

${kernel} void LBMCollideAndPropagate(${kernel_args()})
{
	${local_indices()}

	// shared variables for in-block propagation
	%for i in sym.get_prop_dists(grid, 1):
		${shared_var} float prop_${grid.idx_name[i]}[BLOCK_SIZE];
	%endfor
	%for i in sym.get_prop_dists(grid, -1):
		${shared_var} float prop_${grid.idx_name[i]}[BLOCK_SIZE];
	%endfor

	int type, orientation;
	decodeNodeType(map[gi], &orientation, &type);

	// Unused nodes do not participate in the simulation.
	if (isUnusedNode(type))
		return;

	// cache the distributions in local variables
	Dist fi;
	getDist(&fi, dist_in, gi);

	// macroscopic quantities for the current cell
	float rho, v[${dim}];

	getMacro(&fi, type, orientation, &rho, v);
	boundaryConditions(&fi, type, orientation, &rho, v);
	${barrier()}

	// only save the macroscopic quantities if requested to do so
	if (save_macro == 1) {
		orho[gi] = rho;
		ovx[gi] = v[0];
		ovy[gi] = v[1];
		%if dim == 3:
			ovz[gi] = v[2];
		%endif
	}

	${relaxate()}
	${propagate()}
}
