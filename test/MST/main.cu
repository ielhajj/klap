/** Minimum spanning tree -*- C++ -*-
 * @file
 * @section License
 *
 * Galois, a framework to exploit amorphous data-parallelism in irregular
 * programs.
 *
 * Copyright (C) 2013, The University of Texas at Austin. All rights reserved.
 * UNIVERSITY EXPRESSLY DISCLAIMS ANY AND ALL WARRANTIES CONCERNING THIS
 * SOFTWARE AND DOCUMENTATION, INCLUDING ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR ANY PARTICULAR PURPOSE, NON-INFRINGEMENT AND WARRANTIES OF
 * PERFORMANCE, AND ANY WARRANTY THAT MIGHT OTHERWISE ARISE FROM COURSE OF
 * DEALING OR USAGE OF TRADE.  NO WARRANTY IS EITHER EXPRESS OR IMPLIED WITH
 * RESPECT TO THE USE OF THE SOFTWARE OR DOCUMENTATION. Under no circumstances
 * shall University be liable for incidental, special, indirect, direct or
 * consequential damages or loss of profits, interruption of business, or
 * related expenses which may arise from use of Software or Documentation,
 * including but not limited to those resulting from defects in Software and/or
 * Documentation, or loss or inaccuracy of data of any kind.
 *
 * @Description
 * Computes minimum spanning tree of a graph using Boruvka's algorithm.
 *
 * @author Rupesh Nasre <nasre@ices.utexas.edu>
 * @author Sreepathi Pai <sreepai@ices.utexas.edu>
 */

#include "common.h"
#include "lonestargpu/cuda_launch_config.hpp"
#include "lonestargpu/gbar.cuh"

__global__ void dinit(unsigned *mstwt, Graph graph, ComponentSpace cs, foru *eleminwts, foru *minwtcomponent, unsigned *partners, unsigned *phores, bool *processinnextiteration, unsigned *goaheadnodeofcomponent, unsigned inpid) {
    unsigned id = blockIdx.x * blockDim.x + threadIdx.x;
    if (inpid < graph.nnodes) id = inpid;

    if (id < graph.nnodes) {
        eleminwts[id] = MYINFINITY;
        minwtcomponent[id] = MYINFINITY;
        goaheadnodeofcomponent[id] = graph.nnodes;
        phores[id] = 0;
        partners[id] = id;
        processinnextiteration[id] = false;
    }
}

__global__ void dfindelemin(unsigned *mstwt, Graph graph, ComponentSpace cs, foru *eleminwts, foru *minwtcomponent, unsigned *partners, unsigned *phore, bool *processinnextiteration, unsigned *goaheadnodeofcomponent, unsigned inpid) {
    unsigned id = blockIdx.x * blockDim.x + threadIdx.x;
    if (inpid < graph.nnodes) id = inpid;

    if (id < graph.nnodes) {
        // if I have a cross-component edge,
        // 	find my minimum wt cross-component edge,
        //	inform my boss about this edge e (atomicMin).
        unsigned src = id;
        unsigned srcboss = cs.find(src);
        unsigned dstboss = graph.nnodes;
        foru minwt = MYINFINITY;
        unsigned degree = graph.getOutDegree(src);
        for (unsigned ii = 0; ii < degree; ++ii) {
            foru wt = graph.getWeight(src, ii);
            if (wt < minwt) {
                unsigned dst = graph.getDestination(src, ii);
                unsigned tempdstboss = cs.find(dst);
                if (srcboss != tempdstboss) {	// cross-component edge.
                    minwt = wt;
                    dstboss = tempdstboss;
                }
            }
        }
        dprintf("\tminwt[%d] = %d\n", id, minwt);
        eleminwts[id] = minwt;
        partners[id] = dstboss;

        if (minwt < minwtcomponent[srcboss] && srcboss != dstboss) {
            // inform boss.
            foru oldminwt = atomicMin(&minwtcomponent[srcboss], minwt);
            // if (oldminwt > minwt && minwtcomponent[srcboss] == minwt)
            //   {
            // 	goaheadnodeofcomponent[srcboss],id);	// threads with same wt edge will race.
            // 	dprintf("\tpartner[%d(%d)] = %d init, eleminwts[id]=%d\n", id, srcboss, dstboss, eleminwts[id]);
            //   }
        }
    }
}

__global__ void elim_dups(unsigned *mstwt, Graph graph, ComponentSpace cs, foru *eleminwts, foru *minwtcomponent, unsigned *partners, unsigned *phore, bool *processinnextiteration, unsigned *goaheadnodeofcomponent, unsigned inpid) {
    unsigned id = blockIdx.x * blockDim.x + threadIdx.x;
    if (inpid < graph.nnodes) id = inpid;

    if (id < graph.nnodes) {
        if(processinnextiteration[id])
        {
            unsigned srcc = cs.find(id);
            unsigned dstc = partners[id];

            if(minwtcomponent[dstc] == eleminwts[id])
            {
                if(id < goaheadnodeofcomponent[dstc])
                {
                    processinnextiteration[id] = false;
                    //printf("duplicate!\n");
                }
            }
        }
    }
}

__global__ void dfindcompmin(unsigned *mstwt, Graph graph, ComponentSpace cs, foru *eleminwts, foru *minwtcomponent, unsigned *partners, unsigned *phores, bool *processinnextiteration, unsigned *goaheadnodeofcomponent, unsigned inpid) {
    unsigned id = blockIdx.x * blockDim.x + threadIdx.x;
    if (inpid < graph.nnodes) id = inpid;

    if (id < graph.nnodes) {
        if(partners[id] == graph.nnodes)
            return;

        unsigned srcboss = cs.find(id);
        unsigned dstboss = cs.find(partners[id]);
        if (id != partners[id] && srcboss != dstboss && eleminwts[id] != MYINFINITY && minwtcomponent[srcboss] == eleminwts[id] && dstboss != id && goaheadnodeofcomponent[srcboss] == id) {	// my edge is min outgoing-component edge.
            if(!processinnextiteration[id]);
            //printf("whoa!\n");
            //= true;
        }
        else
        {
            if(processinnextiteration[id]);
            //printf("whoa2!\n");
        }
    }
}

__global__ void dfindcompmintwo(unsigned *mstwt, Graph graph, ComponentSpace csw, foru *eleminwts, foru *minwtcomponent, unsigned *partners, unsigned *phores, bool *processinnextiteration, unsigned *goaheadnodeofcomponent, unsigned inpid, GlobalBarrier gb, bool *repeat, unsigned *count) {
    unsigned tid = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned id, nthreads = blockDim.x * gridDim.x;
    if (inpid < graph.nnodes) id = inpid;

    unsigned up = (graph.nnodes + nthreads - 1) / nthreads * nthreads;
    unsigned srcboss, dstboss;


    for(id = tid; id < up; id += nthreads) {
        if(id < graph.nnodes && processinnextiteration[id])
        {
            srcboss = csw.find(id);
            dstboss = csw.find(partners[id]);
        }

        gb.Sync();

        if (id < graph.nnodes && processinnextiteration[id] && srcboss != dstboss) {
            dprintf("trying unify id=%d (%d -> %d)\n", id, srcboss, dstboss);

            if (csw.unify(srcboss, dstboss)) {
                atomicAdd(mstwt, eleminwts[id]);
                atomicAdd(count, 1);
                dprintf("u %d -> %d (%d)\n", srcboss, dstboss, eleminwts[id]);
                processinnextiteration[id] = false;
                eleminwts[id] = MYINFINITY;	// mark end of processing to avoid getting repeated.
            }
            else {
                *repeat = true;
            }

            dprintf("\tcomp[%d] = %d.\n", srcboss, csw.find(srcboss));
        }

        gb.Sync();
    }
}

__global__ void dfindcompmintwo_serial(unsigned *mstwt, Graph graph, ComponentSpace csr, ComponentSpace csw, foru *eleminwts, foru *minwtcomponent, unsigned *partners, unsigned *phores, bool *processinnextiteration, unsigned *goaheadnodeofcomponent, unsigned inpid, GlobalBarrier gb, bool *repeat, unsigned *count) {
    unsigned id;
    if (inpid < graph.nnodes) id = inpid;

    unsigned srcboss, dstboss;

    if(id < graph.nnodes && processinnextiteration[id])
    {
        srcboss = csw.find(id);
        dstboss = csw.find(partners[id]);
    }

    gb.Sync();

    if (id < graph.nnodes && processinnextiteration[id] && srcboss != dstboss) {
        dprintf("trying unify id=%d (%d -> %d)\n", id, srcboss, dstboss);

        if (csw.unify(srcboss, dstboss)) {
            atomicAdd(mstwt, eleminwts[id]);
            //atomicAdd(count, 1);
            dprintf("u %d -> %d (%d)\n", srcboss, dstboss, eleminwts[id]);
            processinnextiteration[id] = false;
            eleminwts[id] = MYINFINITY;	// mark end of processing to avoid getting repeated.
        }
        else {
            *repeat = true;
        }

        dprintf("\tcomp[%d] = %d.\n", srcboss, csw.find(srcboss));
    }

    gb.Sync(); 
}

void print_comp_mins(ComponentSpace cs, Graph graph, foru *minwtcomponent, unsigned *goaheadnodeofcomponent, unsigned *partners, bool *pin)
{
    foru *cminwt;
    unsigned *cgah, *cpart;
    unsigned *ele2comp;
    bool *cpin;

    ele2comp = (unsigned *) calloc(cs.nelements, sizeof(unsigned));
    cgah = (unsigned *) calloc(cs.nelements, sizeof(unsigned));
    cpart = (unsigned *) calloc(cs.nelements, sizeof(unsigned));
    cminwt = (foru *) calloc(cs.nelements, sizeof(unsigned));
    cpin = (bool *) calloc(cs.nelements, sizeof(bool));


    assert(cudaMemcpy(ele2comp, cs.ele2comp, cs.nelements * sizeof(unsigned), cudaMemcpyDeviceToHost) == cudaSuccess);
    assert(cudaMemcpy(cgah, goaheadnodeofcomponent, cs.nelements * sizeof(unsigned), cudaMemcpyDeviceToHost) == cudaSuccess);
    assert(cudaMemcpy(cminwt, minwtcomponent, cs.nelements * sizeof(unsigned), cudaMemcpyDeviceToHost) == cudaSuccess);
    assert(cudaMemcpy(cpart, partners, cs.nelements * sizeof(unsigned), cudaMemcpyDeviceToHost) == cudaSuccess);
    assert(cudaMemcpy(cpin, pin, cs.nelements * sizeof(bool), cudaMemcpyDeviceToHost) == cudaSuccess);

    for(int i = 0; i < cs.nelements; i++)
    {
        if(ele2comp[i] == i && cminwt[i] != MYINFINITY && cpin[cgah[i]])
            printf("CM %d %d %d %d\n",  i, cminwt[i], cgah[i], cpart[i]);
    }

    free(ele2comp);
    free(cgah);
    free(cminwt);
}

int main(int argc, char *argv[]) {

    // Parameters
    int warmup              = 1;
    int runs                = 3;
    int outputLevel         = 1;
    const char* graphFile   = "inputs/rmat12.sym.gr";
    int opt;
    while((opt = getopt(argc, argv, "w:r:o:g:h")) >= 0) {
        switch(opt) {
            case 'w': warmup        = atoi(optarg); break;
            case 'r': runs          = atoi(optarg); break;
            case 'o': outputLevel   = atoi(optarg); break;
            case 'g': graphFile     = optarg      ; break;
            default : std::cerr <<
                      "\nUsage:  ./mst [options]"
                          "\n"
                          "\n    -w <W>    # of warmup runs (default=1)"
                          "\n    -r <R>    # of timed runs (default=3)"
                          "\n    -o <O>    level of output verbosity (0: one CSV row, 1: moderate, 2: verbose)"
                          "\n    -g <G>    graph file name (default=inputs/rmat12.sym.gr)"
                          "\n    -h        help\n\n";
                      exit(0);
        }
    }

    int iteration;
    KernelConfig kconf;
    const int nSM = kconf.getNumberOfSMs();

    double starttime, endtime;
    double starttime2, endtime2, time2;
    double starttime3, endtime3, time3;
    GlobalBarrierLifetime gb;
    const size_t compmintwo_res = maximum_residency(dfindcompmintwo, 384, 0);
    gb.Setup(nSM * compmintwo_res);

    unsigned *mstwt, hmstwt;
    Graph hgraph, graph;
    hgraph.read((char*)graphFile);
    hgraph.cudaCopy(graph);

    kconf.setProblemSize(graph.nnodes);
    kconf.setMaxThreadsPerBlock();

    unsigned *partners, *phores;
    foru *eleminwts, *minwtcomponent;
    bool *processinnextiteration;
    unsigned *goaheadnodeofcomponent;
    unsigned prevncomponents, currncomponents = graph.nnodes;
    bool repeat, *grepeat;
    unsigned edgecount, *gedgecount;
    if (cudaMalloc((void **)&mstwt, sizeof(unsigned)) != cudaSuccess) CudaTest("allocating mstwt failed");
    if (cudaMalloc((void **)&eleminwts, graph.nnodes * sizeof(foru)) != cudaSuccess) CudaTest("allocating eleminwts failed");
    if (cudaMalloc((void **)&minwtcomponent, graph.nnodes * sizeof(foru)) != cudaSuccess) CudaTest("allocating minwtcomponent failed");
    if (cudaMalloc((void **)&partners, graph.nnodes * sizeof(unsigned)) != cudaSuccess) CudaTest("allocating partners failed");
    if (cudaMalloc((void **)&phores, graph.nnodes * sizeof(unsigned)) != cudaSuccess) CudaTest("allocating phores failed");
    if (cudaMalloc((void **)&processinnextiteration, graph.nnodes * sizeof(bool)) != cudaSuccess) CudaTest("allocating processinnextiteration failed");
    if (cudaMalloc((void **)&goaheadnodeofcomponent, graph.nnodes * sizeof(unsigned)) != cudaSuccess) CudaTest("allocating goaheadnodeofcomponent failed");
    CUDA_SAFE_CALL(cudaMalloc(&grepeat, sizeof(bool) * 1));
    CUDA_SAFE_CALL(cudaMalloc(&gedgecount, sizeof(unsigned) * 1));

    float totalFindKernelTime = 0;
    float totalVerifyKernelTime = 0;
    for(int run = -warmup; run < runs; run++) {

        if(outputLevel >= 1) {
            if(run < 0) {
                std::cout << "Warmup:\n";
            } else {
                std::cout << "Run " << run << ":\n";
            }
        }

        ComponentSpace cs(graph.nnodes);
        hmstwt = 0;
        repeat = false;
        edgecount = 0;
        CUDA_SAFE_CALL(cudaMemcpy(mstwt, &hmstwt, sizeof(hmstwt), cudaMemcpyHostToDevice));	// mstwt = 0.
        CUDA_SAFE_CALL(cudaMemcpy(grepeat, &repeat, sizeof(bool) * 1, cudaMemcpyHostToDevice));
        CUDA_SAFE_CALL(cudaMemcpy(gedgecount, &edgecount, sizeof(unsigned) * 1, cudaMemcpyHostToDevice));

        starttime = rtclock();
        time2 = 0;
        time3 = 0;
        cudaDeviceSetLimit(cudaLimitDevRuntimePendingLaunchCount, graph.nnodes); // Fixed-size pool
        iteration = 0;
        do {
            ++iteration;
            prevncomponents = currncomponents;
            dinit<<<kconf.getNumberOfBlocks(), kconf.getNumberOfBlockThreads()>>>(mstwt, graph, cs, eleminwts, minwtcomponent, partners, phores, processinnextiteration, goaheadnodeofcomponent, graph.nnodes);
            cudaDeviceSynchronize();
            CudaTest("dinit failed");
            dfindelemin<<<kconf.getNumberOfBlocks(), kconf.getNumberOfBlockThreads()>>>(mstwt, graph, cs, eleminwts, minwtcomponent, partners, phores, processinnextiteration, goaheadnodeofcomponent, graph.nnodes);
            cudaDeviceSynchronize();
            CudaTest("dfindelemin failed");
            starttime2 = rtclock();
            launch_find_kernel(kconf.getNumberOfBlocks(), kconf.getNumberOfBlockThreads(), mstwt, graph, cs, eleminwts, minwtcomponent, partners, phores, processinnextiteration, goaheadnodeofcomponent, graph.nnodes);
            cudaDeviceSynchronize();
            endtime2 = rtclock();
            CudaTest("find kernel failed");
            time2 += (endtime2 - starttime2);
            starttime3 = rtclock();
            launch_verify_kernel(kconf.getNumberOfBlocks(), kconf.getNumberOfBlockThreads(), mstwt, graph, cs, eleminwts, minwtcomponent, partners, phores, processinnextiteration, goaheadnodeofcomponent, graph.nnodes);
            cudaDeviceSynchronize();
            endtime3 = rtclock();
            CudaTest("verify kernel failed");
            time3 += (endtime3 - starttime3);
            if(debug) print_comp_mins(cs, graph, minwtcomponent, goaheadnodeofcomponent, partners, processinnextiteration);
            do {
                repeat = false;
                CUDA_SAFE_CALL(cudaMemcpy(grepeat, &repeat, sizeof(bool) * 1, cudaMemcpyHostToDevice));
                dfindcompmintwo<<<nSM * compmintwo_res, 384>>> (mstwt, graph, cs, eleminwts, minwtcomponent, partners, phores, processinnextiteration, goaheadnodeofcomponent, graph.nnodes, gb, grepeat, gedgecount);
                CudaTest("dfindcompmintwo failed");
                CUDA_SAFE_CALL(cudaMemcpy(&repeat, grepeat, sizeof(bool) * 1, cudaMemcpyDeviceToHost));
            } while (repeat); // only required for quicker convergence?
            currncomponents = cs.numberOfComponentsHost();
            CUDA_SAFE_CALL(cudaMemcpy(&hmstwt, mstwt, sizeof(hmstwt), cudaMemcpyDeviceToHost));
            CUDA_SAFE_CALL(cudaMemcpy(&edgecount, gedgecount, sizeof(unsigned) * 1, cudaMemcpyDeviceToHost));
            if(outputLevel >= 1) printf("\titeration %d, number of components = %d (%d), mstwt = %u, mstedges = %u\n", iteration, currncomponents, prevncomponents, hmstwt, edgecount);
        } while (currncomponents != prevncomponents);
        CUDA_SAFE_CALL(cudaDeviceSynchronize());
        endtime = rtclock();
        if(outputLevel >= 1) printf("\tOverall: mstwt = %u, iterations = %d, ", hmstwt, iteration);
        //printf("\t%s result: weight: %u, components: %u, edges: %u\n", graphFile, hmstwt, currncomponents, edgecount);
        if(outputLevel >= 1) printf("dfind2 [mst] = %f ms, ", 1000 * time2);
        if(run >= 0) totalFindKernelTime += time2;
        if(outputLevel >= 1) printf("verify_min_elem [mst] = %f ms, ", 1000 * time3);
        if(run >= 0) totalVerifyKernelTime += time3;
        if(outputLevel >= 1) printf("\ttotal runtime [mst] = %f ms.\n", 1000 * (endtime - starttime));
        //printf("grid size=%d, block size=%d\n\n", kconf.getNumberOfBlocks(), kconf.getNumberOfBlockThreads());

    }

    if(outputLevel >= 1) {
        std::cout<<"Average find kernel time = " << totalFindKernelTime/runs*1000 << " ms\n";
        std::cout<<"Average verify kernel time = " << totalVerifyKernelTime/runs*1000 << " ms\n";
    } else {
        std::cout<< totalFindKernelTime/runs*1000 << ",";
        std::cout<< totalVerifyKernelTime/runs*1000;
    }

    // cleanup left to the OS.

    return 0;
}

