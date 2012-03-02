/******************************************************************************
 * 
 * Copyright 2010-2011 Duane Merrill
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License. 
 * 
 * For more information, see our Google Code project site: 
 * http://code.google.com/p/back40computing/
 * 
 * Thanks!
 * 
 ******************************************************************************/

/******************************************************************************
 * Enactor base class
 ******************************************************************************/

#pragma once

#include <b40c/util/cuda_properties.cuh>
#include <b40c/util/cta_work_distribution.cuh>
#include <b40c/util/basic_utils.cuh>
#include <b40c/util/error_utils.cuh>

namespace b40c {
namespace util {



/**
 * Enactor base class
 */
class EnactorBase
{
public:

	//---------------------------------------------------------------------
	// Utility Fields
	//---------------------------------------------------------------------

	// Debug level.  If set, the enactor blocks after kernel calls to check
	// for successful launch/execution
	bool ENACTOR_DEBUG;


	// The arch version of the code for the current device that actually have
	// compiled kernels for
	int PtxVersion()
	{
		return this->cuda_props.kernel_ptx_version;
	}

	// The number of SMs on the current device
	int SmCount()
	{
		return this->cuda_props.device_props.multiProcessorCount;
	}

protected:

	template <typename MyType, typename DerivedType = void>
	struct DispatchType
	{
		typedef DerivedType Type;
	};

	template <typename MyType>
	struct DispatchType<MyType, void>
	{
		typedef MyType Type;
	};


	//---------------------------------------------------------------------
	// Members
	//---------------------------------------------------------------------

	// Device properties
	const util::CudaProperties cuda_props;


	//---------------------------------------------------------------------
	// Tuning Utility Routines
	//---------------------------------------------------------------------

	/**
	 * Computes dynamic smem allocations to ensure all three kernels end up
	 * allocating the same amount of smem per CTA
	 */
	template <
		typename UpsweepKernelPtr,
		typename SpineKernelPtr,
		typename DownsweepKernelPtr>
	cudaError_t PadUniformSmem(
		int dynamic_smem[3],
		UpsweepKernelPtr UpsweepKernel,
		SpineKernelPtr SpineKernel,
		DownsweepKernelPtr DownsweepKernel)
	{
		cudaError_t retval = cudaSuccess;
		do {

			// Get kernel attributes
			cudaFuncAttributes upsweep_kernel_attrs, spine_kernel_attrs, downsweep_kernel_attrs;
			if (retval = util::B40CPerror(cudaFuncGetAttributes(&upsweep_kernel_attrs, UpsweepKernel),
				"EnactorBase cudaFuncGetAttributes upsweep_kernel_attrs failed", __FILE__, __LINE__)) break;
			if (retval = util::B40CPerror(cudaFuncGetAttributes(&spine_kernel_attrs, SpineKernel),
				"EnactorBase cudaFuncGetAttributes spine_kernel_attrs failed", __FILE__, __LINE__)) break;
			if (retval = util::B40CPerror(cudaFuncGetAttributes(&downsweep_kernel_attrs, DownsweepKernel),
				"EnactorBase cudaFuncGetAttributes spine_kernel_attrs failed", __FILE__, __LINE__)) break;

			int max_static_smem = B40C_MAX(
				upsweep_kernel_attrs.sharedSizeBytes,
				B40C_MAX(spine_kernel_attrs.sharedSizeBytes, downsweep_kernel_attrs.sharedSizeBytes));

			dynamic_smem[0] = max_static_smem - upsweep_kernel_attrs.sharedSizeBytes;
			dynamic_smem[1] = max_static_smem - spine_kernel_attrs.sharedSizeBytes;
			dynamic_smem[2] = max_static_smem - downsweep_kernel_attrs.sharedSizeBytes;

		} while (0);

		return retval;
	}


	/**
	 * Computes dynamic smem allocations to ensure both kernels end up
	 * allocating the same amount of smem per CTA
	 */
	template <
		typename UpsweepKernelPtr,
		typename SpineKernelPtr>
	cudaError_t PadUniformSmem(
		int dynamic_smem[2],				// out param
		UpsweepKernelPtr UpsweepKernel,
		SpineKernelPtr SpineKernel)
	{
		cudaError_t retval = cudaSuccess;
		do {

			// Get kernel attributes
			cudaFuncAttributes upsweep_kernel_attrs, spine_kernel_attrs;
			if (retval = util::B40CPerror(cudaFuncGetAttributes(&upsweep_kernel_attrs, UpsweepKernel),
				"EnactorBase cudaFuncGetAttributes upsweep_kernel_attrs failed", __FILE__, __LINE__)) break;
			if (retval = util::B40CPerror(cudaFuncGetAttributes(&spine_kernel_attrs, SpineKernel),
				"EnactorBase cudaFuncGetAttributes spine_kernel_attrs failed", __FILE__, __LINE__)) break;

			int max_static_smem = B40C_MAX(
				upsweep_kernel_attrs.sharedSizeBytes,
				spine_kernel_attrs.sharedSizeBytes);

			dynamic_smem[0] = max_static_smem - upsweep_kernel_attrs.sharedSizeBytes;
			dynamic_smem[1] = max_static_smem - spine_kernel_attrs.sharedSizeBytes;

		} while (0);

		return retval;
	}


	template <typename KernelPtr>
	cudaError_t MaxCtaOccupancy(
		int &max_cta_occupancy,					// out param
		KernelPtr Kernel,
		int threads)
	{
		cudaError_t retval = cudaSuccess;
		do {
			// Get kernel attributes
			cudaFuncAttributes kernel_attrs;
			if (retval = util::B40CPerror(cudaFuncGetAttributes(&kernel_attrs, Kernel),
				"EnactorBase cudaFuncGetAttributes kernel_attrs failed", __FILE__, __LINE__)) break;

			// 128B aligned sections
			int shared = ((kernel_attrs.sharedSizeBytes + 128 - 1) / 128) * 128;

			max_cta_occupancy = B40C_MIN(
				B40C_SM_CTAS(cuda_props.device_sm_version),
				B40C_MIN(
					B40C_SMEM_BYTES(cuda_props.device_sm_version) / shared,
					B40C_SM_REGISTERS(cuda_props.device_sm_version) / (kernel_attrs.numRegs * threads)));

		} while (0);

		return retval;

	}

	template <
		typename UpsweepKernelPtr,
		typename DownsweepKernelPtr>
	cudaError_t MaxCtaOccupancy(
		int &max_cta_occupancy,					// out param
		UpsweepKernelPtr UpsweepKernel,
		int upsweep_threads,
		DownsweepKernelPtr DownsweepKernel,
		int downsweep_threads)
	{
		cudaError_t retval = cudaSuccess;
		do {
			int upsweep_cta_occupancy, downsweep_cta_occupancy;

			if (retval = MaxCtaOccupancy(upsweep_cta_occupancy, UpsweepKernel, upsweep_threads)) break;
			if (retval = MaxCtaOccupancy(downsweep_cta_occupancy, DownsweepKernel, downsweep_threads)) break;

			if (ENACTOR_DEBUG) printf("Occupancy:\t[upsweep occupancy: %d, downsweep occupancy %d]\n",
				upsweep_cta_occupancy, downsweep_cta_occupancy);

			max_cta_occupancy = B40C_MIN(upsweep_cta_occupancy, downsweep_cta_occupancy);

		} while (0);

		return retval;

	}



	/**
	 * Returns the number of threadblocks to launch for the given problem size.
	 * Does not exceed the full-occupancy on the current device or the
	 * optional max_grid_size limit.
	 *
	 * Useful for kernels that work-steal or use global barriers (where
	 * over-subscription is not ideal or allowed)
	 */
	int OccupiedGridSize(
		int schedule_granularity,
		int max_cta_occupancy,
		int num_elements,
		int max_grid_size = 0)
	{
		int grid_size;

		if (max_grid_size > 0) {
			grid_size = max_grid_size;
		} else {
			grid_size = cuda_props.device_props.multiProcessorCount * max_cta_occupancy;
		}

		// Reduce if we have less work than we can divide up among this
		// many CTAs
		int grains = (num_elements + schedule_granularity - 1) / schedule_granularity;
		if (grid_size > grains) {
			grid_size = grains;
		}


		return grid_size;
	}


	/**
	 * Returns the number of threadblocks to launch for the given problem size.
	 * May over/under subscribe the current device based upon heuristics.  Does not
	 * the optional max_grid_size limit.
	 *
	 * Useful for kernels that evenly divide up the work amongst threadblocks.
	 */
	int OversubscribedGridSize(
		int num_elements,
		int max_grid_size,
		int schedule_granularity,
		int upsweep_occupancy,
		int downsweep_occupancy = -1)
	{
		int grid_size;
		int grains = (num_elements + schedule_granularity - 1) / schedule_granularity;
		if (downsweep_occupancy == -1) downsweep_occupancy = upsweep_occupancy;
		int min_cta_occupancy = B40C_MIN(upsweep_occupancy, downsweep_occupancy);

		if (cuda_props.device_sm_version < 120) {

			// G80/G90: double CTA occupancy times SM count
			grid_size = (max_grid_size > 0) ?
				max_grid_size :
				cuda_props.device_props.multiProcessorCount * min_cta_occupancy * 2;

		} else if (cuda_props.device_sm_version < 200) {

			// GT200: Special sauce

			// Start with with full downsweep occupancy of all SMs
			grid_size = cuda_props.device_props.multiProcessorCount * min_cta_occupancy;

			int bumps = 0;
			double cutoff = 0.005;

			while (true) {

				double quotient = double(num_elements) /
					grid_size /
					schedule_granularity;
				int log = log2(quotient) + 0.5;
				int primary = (1 << log) *
					grid_size *
					schedule_granularity;

				double ratio = double(num_elements) / primary;
/*
				printf("log %d, num_elements %d, primary %d, ratio %f\n",
					log,
					num_elements,
					primary,
					ratio);
*/
				if (((ratio < 1.00 + cutoff) && (ratio > 1.00 - cutoff)) ||
					((ratio < 0.75 + cutoff) && (ratio > 0.75 - cutoff)) ||
					((ratio < 0.50 + cutoff) && (ratio > 0.50 - cutoff)) ||
					((ratio < 0.25 + cutoff) && (ratio > 0.25 - cutoff)))
				{
					if (bumps == 3) {
						// Bump it up by 33
						grid_size += 33;
						bumps = 0;
					} else {
						// Bump it down by 1
						grid_size--;
						bumps++;
					}
					continue;
				}

				break;
			}

			grid_size = B40C_MIN(
				grains,
				((max_grid_size > 0) ?
					max_grid_size :
					grid_size));

		} else {

			// GF10x
			grid_size = B40C_MIN(
				grains,
				((max_grid_size > 0) ?
					max_grid_size :
					(upsweep_occupancy * downsweep_occupancy * cuda_props.device_props.multiProcessorCount) - 1));
		}

		return grid_size;
	}


	//-----------------------------------------------------------------------------
	// Debug Utility Routines
	//-----------------------------------------------------------------------------

	/**
	 * Utility method to display the contents of a device array
	 */
	template <typename T>
	void DisplayDeviceResults(
		T *d_data,
		size_t num_elements)
	{
		// Allocate array on host and copy back
		T *h_data = (T*) malloc(num_elements * sizeof(T));
		cudaMemcpy(h_data, d_data, sizeof(T) * num_elements, cudaMemcpyDeviceToHost);

		// Display data
		for (int i = 0; i < num_elements; i++) {
			PrintValue(h_data[i]);
			printf(", ");
		}
		printf("\n\n");

		// Cleanup
		if (h_data) free(h_data);
	}


	/**
	 * Prints key size information
	 */
	template <typename KernelPolicy>
	bool PrintKeySizeInfo(typename KernelPolicy::KeyType *ptr) {
		printf("%lu byte keys, ", (unsigned long) sizeof(typename KernelPolicy::KeyType));
		return true;
	}
	template <typename KernelPolicy>
	bool PrintKeySizeInfo(...) {return false;}

	/**
	 * Prints value size information
	 */
	template <typename KernelPolicy>
	bool PrintValueSizeInfo(typename KernelPolicy::ValueType *ptr) {
		if (!util::Equals<typename KernelPolicy::ValueType, util::NullType>::VALUE) {
			printf("%lu byte values, ", (unsigned long) sizeof(typename KernelPolicy::ValueType));
		}
		return true;
	}
	template <typename KernelPolicy>
	bool PrintValueSizeInfo(...) {return false;}

	/**
	 * Prints T size information
	 */
	template <typename KernelPolicy>
	bool PrintTSizeInfo(typename KernelPolicy::T *ptr) {
		printf("%lu byte data, ", (unsigned long) sizeof(typename KernelPolicy::T));
		return true;
	}
	template <typename KernelPolicy>
	bool PrintTSizeInfo(...) {return false;}

	/**
	 * Prints workstealing information
	 */
	template <typename KernelPolicy>
	bool PrintWorkstealingInfo(int (*data)[KernelPolicy::WORK_STEALING + 1]) {
		printf("%sworkstealing, ", (KernelPolicy::WORK_STEALING) ? "" : "non-");
		return true;
	}
	template <typename KernelPolicy>
	bool PrintWorkstealingInfo(...) {return false;}

	/**
	 * Prints work distribution information
	 */
	template <typename KernelPolicy, typename SizeT>
	void PrintWorkInfo(util::CtaWorkDistribution<SizeT> &work)
	{
		printf("Work: \t\t[");
		if (PrintKeySizeInfo<KernelPolicy>(NULL)) {
			PrintValueSizeInfo<KernelPolicy>(NULL);
		} else {
			PrintTSizeInfo<KernelPolicy>(NULL);
		}
		PrintWorkstealingInfo<KernelPolicy>(NULL);

		unsigned long last_grain_elements =
			(work.num_elements & (KernelPolicy::SCHEDULE_GRANULARITY - 1));
		if (last_grain_elements == 0) last_grain_elements = KernelPolicy::SCHEDULE_GRANULARITY;

		printf("%lu byte SizeT, "
				"%lu elements, "
				"%lu-element granularity, "
				"%lu total grains, "
				"%lu grains per cta, "
				"%lu extra grains, "
				"%lu last-grain elements]\n",
			(unsigned long) sizeof(SizeT),
			(unsigned long) work.num_elements,
			(unsigned long) KernelPolicy::SCHEDULE_GRANULARITY,
			(unsigned long) work.total_grains,
			(unsigned long) work.grains_per_cta,
			(unsigned long) work.extra_grains,
			(unsigned long) last_grain_elements);
		fflush(stdout);
	}


	/**
	 * Prints pass information
	 */
	template <typename UpsweepPolicy, typename SizeT>
	void PrintPassInfo(
		util::CtaWorkDistribution<SizeT> &work,
		int spine_elements = 0)
	{
		printf("CodeGen: \t[device_sm_version: %d, kernel_ptx_version: %d, SM count: %d]\n",
			cuda_props.device_sm_version,
			cuda_props.kernel_ptx_version,
			cuda_props.device_props.multiProcessorCount);
		PrintWorkInfo<UpsweepPolicy, SizeT>(work);
		printf("Upsweep: \t[sweep_grid_size: %d, threads %d, tile_elements: %d]\n",
			work.grid_size,
			UpsweepPolicy::THREADS,
			UpsweepPolicy::TILE_ELEMENTS);
		fflush(stdout);
	}

	/**
	 * Prints pass information
	 */
	template <typename UpsweepPolicy, typename SpinePolicy, typename SizeT>
	void PrintPassInfo(
		util::CtaWorkDistribution<SizeT> &work,
		int spine_elements = 0)
	{
		PrintPassInfo<UpsweepPolicy>(work);
		printf("Spine: \t\t[threads: %d, spine_elements: %d, tile_elements: %d]\n",
			SpinePolicy::THREADS,
			spine_elements,
			SpinePolicy::TILE_ELEMENTS);
		fflush(stdout);
	}

	/**
	 * Prints pass information
	 */
	template <typename UpsweepPolicy, typename SpinePolicy, typename DownsweepPolicy, typename SizeT>
	void PrintPassInfo(
		util::CtaWorkDistribution<SizeT> &work,
		int spine_elements = 0)
	{
		PrintPassInfo<UpsweepPolicy, SpinePolicy>(work, spine_elements);
		printf("Downsweep: \t[sweep_grid_size: %d, threads %d, tile_elements: %d]\n",
			work.grid_size,
			DownsweepPolicy::THREADS,
			DownsweepPolicy::TILE_ELEMENTS);
		fflush(stdout);
	}




	//---------------------------------------------------------------------
	// Constructors
	//---------------------------------------------------------------------

	EnactorBase() :
#if	defined(__THRUST_SYNCHRONOUS) || defined(DEBUG) || defined(_DEBUG)
			ENACTOR_DEBUG(true)
#else
			ENACTOR_DEBUG(false)
#endif
		{}

};


} // namespace util
} // namespace b40c
