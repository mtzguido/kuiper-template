
#include "KuiperTemplate_Increment.h"

__global__
/**
  hoisted when extracting run
*/
static void
__hoisted_run_0(uint64_t *device_value)
{
    (*device_value)++;
}

uint64_t KuiperTemplate_Increment_run(void)
{
    uint64_t host_value = 41ULL;
    uint64_t *device_value = (uint64_t *) KPR_GPU_ALLOC(sizeof(uint64_t), 1U);
    MUST(cudaMemcpy(device_value, &host_value, sizeof(uint64_t),
                    cudaMemcpyHostToDevice));
    cudaStream_t s = KPR_FRESH_STREAM();
    KPR_KCALL(__hoisted_run_0, 1U, 1U, 0U, s, device_value);
    MUST(cudaStreamSynchronize(s));
    MUST(cudaStreamDestroy(s));
    MUST(cudaMemcpy(&host_value, device_value, sizeof(uint64_t),
                    cudaMemcpyDeviceToHost));
    uint64_t value = host_value;
    MUST(cudaFree(device_value));
    return value;
}
