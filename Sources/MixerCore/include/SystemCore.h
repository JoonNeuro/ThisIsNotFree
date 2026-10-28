#ifndef SYSTEM_CORE_H
#define SYSTEM_CORE_H
#include <stdint.h>

typedef struct {
    uint64_t busy;
    uint64_t idle;
} TNFCPUTicks;

int TNFReadCPUTicks(TNFCPUTicks *ticks);
uint64_t TNFMemoryUsed(void);
// Returns -1 when the driver does not publish a system GPU utilization counter.
double TNFGPUUsage(void);
typedef struct { uint64_t received; uint64_t sent; } TNFNetworkBytes;
TNFNetworkBytes TNFReadNetworkBytes(void);
double TNFBatteryLevel(void);
uint32_t TNFKeepAwakeBegin(void);
void TNFKeepAwakeEnd(uint32_t assertion);
#endif
