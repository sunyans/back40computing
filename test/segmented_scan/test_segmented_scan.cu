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
 ******************************************************************************/


/******************************************************************************
 * Simple test driver program for segmented scan.
 ******************************************************************************/

#include <stdio.h> 

// Test utils
#include "b40c_test_util.h"
#include "test_segmented_scan.h"

using namespace b40c;

/******************************************************************************
 * Defines, constants, globals
 ******************************************************************************/

bool 	g_verbose 						= false;
bool 	g_sweep							= false;
int 	g_max_ctas 						= 0;
int 	g_iterations  					= 1;
bool 	g_inclusive						= false;


/******************************************************************************
 * Utility Routines
 ******************************************************************************/

/**
 * Displays the commandline usage for this tool
 */
void Usage()
{
	printf("\ntest_segmented_scan [--device=<device index>] [--v] [--i=<num-iterations>] "
			"[--max-ctas=<max-thread-blocks>] [--n=<num-elements>] [--inclusive] [--sweep]\n");
	printf("\n");
	printf("\t--v\tDisplays copied results to the console.\n");
	printf("\n");
	printf("\t--i\tPerforms the segmented scan operation <num-iterations> times\n");
	printf("\t\t\ton the device. Re-copies original input each time. Default = 1\n");
	printf("\n");
	printf("\t--n\tThe number of elements to comprise the sample problem\n");
	printf("\t\t\tDefault = 512\n");
	printf("\n");
}



/**
 * Creates an example segmented scan problem and then dispatches the problem
 * to the GPU for the given number of iterations, displaying runtime information.
 */
template<
	typename T,
	typename Flag,
	bool EXCLUSIVE,
	T BinaryOp(const T&, const T&),
	T Identity()>
void TestSegmentedScan(size_t num_elements)
{
    // Allocate the segmented scan problem on the host and fill the keys with random bytes

	T *h_data 			= (T*) malloc(num_elements * sizeof(T));
	T *h_reference 		= (T*) malloc(num_elements * sizeof(T));
	Flag *h_flag_data	= (Flag*) malloc(num_elements * sizeof(Flag));

	if ((h_data == NULL) || (h_reference == NULL) || (h_flag_data == NULL)){
		fprintf(stderr, "Host malloc of problem data failed\n");
		exit(1);
	}

	for (size_t i = 0; i < num_elements; ++i) {
//		RandomBits<T>(h_data[i], 0);
//		RandomBits<Flag>(h_flag_data[i], 0);
		h_data[i] = 1;
		h_flag_data[i] = (i % 11) == 0;
	}

	for (size_t i = 0; i < num_elements; ++i) {
		if (EXCLUSIVE)
		{
			h_reference[i] = ((i == 0) || (h_flag_data[i])) ?
				Identity() :
				BinaryOp(h_reference[i - 1], h_data[i - 1]);
		} else {
			h_reference[i] = ((i == 0) || (h_flag_data[i])) ?
				h_data[i] :
				BinaryOp(h_reference[i - 1], h_data[i]);
		}
	}

	//
    // Run the timing test(s)
	//

	// Execute test(s), optionally sweeping problem size downward
	size_t orig_num_elements = num_elements;
	do {

		printf("\nLARGE config:\t");
		double large = TimedSegmentedScan<T, Flag, EXCLUSIVE, BinaryOp, Identity, segmented_scan::LARGE>(
			h_data, h_flag_data, h_reference, num_elements, g_max_ctas, g_verbose, g_iterations);

		printf("\nSMALL config:\t");
		double small = TimedSegmentedScan<T, Flag, EXCLUSIVE, BinaryOp, Identity, segmented_scan::SMALL>(
			h_data, h_flag_data, h_reference, num_elements, g_max_ctas, g_verbose, g_iterations);

		if (small > large) {
			printf("%lu-byte elements: Small faster at %lu elements\n",
				(unsigned long) sizeof(T), (unsigned long) num_elements);
		}

		num_elements -= 4096;

	} while (g_sweep && (num_elements < orig_num_elements ));

	// Free our allocated host memory
	if (h_flag_data) free(h_flag_data);
	if (h_data) free(h_data);
    if (h_reference) free(h_reference);
}


/**
 * Creates an example segmented scan problem and then dispatches the problem
 * to the GPU for the given number of iterations, displaying runtime information.
 */
template<
	typename T,
	typename Flag,
	T BinaryOp(const T&, const T&),
	T Identity()>
void TestSegmentedScanVariety(size_t num_elements)
{
	if (g_inclusive) {
		TestSegmentedScan<T, Flag, false, BinaryOp, Identity>(num_elements);
	} else {
		TestSegmentedScan<T, Flag, true, BinaryOp, Identity>(num_elements);
	}
}


/******************************************************************************
 * Main
 ******************************************************************************/

int main(int argc, char** argv)
{

	CommandLineArgs args(argc, argv);
	DeviceInit(args);

	//srand(time(NULL));
	srand(0);				// presently deterministic

    //
	// Check command line arguments
    //

	size_t num_elements = 1024;

    if (args.CheckCmdLineFlag("help")) {
		Usage();
		return 0;
	}

    g_inclusive = args.CheckCmdLineFlag("inclusive");
    g_sweep = args.CheckCmdLineFlag("sweep");
    args.GetCmdLineArgument("i", g_iterations);
    args.GetCmdLineArgument("n", num_elements);
    args.GetCmdLineArgument("max-ctas", g_max_ctas);
	g_verbose = args.CheckCmdLineFlag("v");

	typedef unsigned char Flag;


	{
		printf("\n-- UNSIGNED CHAR ----------------------------------------------\n");
		typedef unsigned char T;
		typedef Sum<T> BinaryOp;
		TestSegmentedScanVariety<T, Flag, BinaryOp::Op, BinaryOp::Identity>(num_elements * 4);
	}
	{
		printf("\n-- UNSIGNED SHORT ----------------------------------------------\n");
		typedef unsigned short T;
		typedef Sum<T> BinaryOp;
		TestSegmentedScanVariety<T, Flag, BinaryOp::Op, BinaryOp::Identity>(num_elements * 2);
	}
	{
		printf("\n-- UNSIGNED INT -----------------------------------------------\n");
		typedef unsigned int T;
		typedef Sum<T> BinaryOp;
		TestSegmentedScanVariety<T, Flag, BinaryOp::Op, BinaryOp::Identity>(num_elements);
	}
	{
		printf("\n-- UNSIGNED LONG LONG -----------------------------------------\n");
		typedef unsigned long long T;
		typedef Sum<T> BinaryOp;
		TestSegmentedScanVariety<T, Flag, BinaryOp::Op, BinaryOp::Identity>(num_elements / 2);
	}

	return 0;
}


