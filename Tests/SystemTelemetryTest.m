#import "SystemCore.h"
#include <stdio.h>
#include <unistd.h>
int main(void) {
    TNFCPUTicks first = {0}, second = {0};
    if (!TNFReadCPUTicks(&first)) return 1;
    usleep(20000);
    if (!TNFReadCPUTicks(&second) || second.busy < first.busy || second.idle < first.idle || second.busy + second.idle == 0) return 1;
    if (!TNFMemoryUsed()) return 1;
    double gpu = TNFGPUUsage();
    if (gpu < -1 || gpu > 100) return 1;
    TNFNetworkBytes bytes = TNFReadNetworkBytes();
    (void)bytes;
    printf("system telemetry: CPU and memory available; GPU %s\n", gpu < 0 ? "counter unavailable" : "counter available");
    return 0;
}
