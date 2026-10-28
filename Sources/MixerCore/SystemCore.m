#import "SystemCore.h"
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>
#include <string.h>

int TNFReadCPUTicks(TNFCPUTicks *ticks) {
    natural_t processors = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t count = 0;
    if (!ticks) return 0;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processors, &info, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return 0;
    ticks->busy = ticks->idle = 0;
    for (natural_t i = 0; i < processors; i++) {
        natural_t offset = i * CPU_STATE_MAX;
        ticks->busy += (uint32_t)info[offset + CPU_STATE_USER] + (uint64_t)(uint32_t)info[offset + CPU_STATE_SYSTEM]
            + (uint32_t)info[offset + CPU_STATE_NICE];
        ticks->idle += (uint32_t)info[offset + CPU_STATE_IDLE];
    }
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
    return 1;
}

uint64_t TNFMemoryUsed(void) {
    vm_statistics64_data_t stats = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&stats, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return 0;
    return ((uint64_t)stats.active_count + stats.wire_count + stats.compressor_page_count) * vm_kernel_page_size;
}

double TNFGPUUsage(void) {
    @autoreleasepool {
        io_iterator_t iterator = 0;
        if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) != KERN_SUCCESS) return -1;
        double usage = -1;
        io_service_t service;
        while ((service = IOIteratorNext(iterator))) {
            CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
            if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                NSDictionary *stats = (__bridge NSDictionary *)value;
                // These driver counters are optional and are not a stable macOS API.
                NSNumber *number = stats[@"Device Utilization %"] ?: stats[@"GPU Activity(%)"];
                if ([number isKindOfClass:NSNumber.class] && number.doubleValue >= 0 && number.doubleValue <= 100)
                    usage = MAX(usage, number.doubleValue);
            }
            if (value) CFRelease(value);
            IOObjectRelease(service);
        }
        IOObjectRelease(iterator);
        return usage;
    }
}

TNFNetworkBytes TNFReadNetworkBytes(void) {
    TNFNetworkBytes result = {0};
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return result;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_LINK || !item->ifa_data ||
            !(item->ifa_flags & IFF_UP) || strncmp(item->ifa_name, "en", 2) != 0) continue;
        struct if_data *data = item->ifa_data;
        result.received += data->ifi_ibytes;
        result.sent += data->ifi_obytes;
    }
    freeifaddrs(interfaces);
    return result;
}

double TNFBatteryLevel(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return -1;
    CFArrayRef sources = IOPSCopyPowerSourcesList(info);
    double result = -1;
    for (CFIndex i = 0; sources && i < CFArrayGetCount(sources); i++) {
        CFDictionaryRef description = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, i));
        NSDictionary *values = (__bridge NSDictionary *)description;
        NSNumber *current = values[@kIOPSCurrentCapacityKey];
        NSNumber *maximum = values[@kIOPSMaxCapacityKey];
        if (current && maximum.doubleValue > 0) { result = current.doubleValue / maximum.doubleValue; break; }
    }
    if (sources) CFRelease(sources);
    CFRelease(info);
    return result;
}

uint32_t TNFKeepAwakeBegin(void) {
    IOPMAssertionID assertion = kIOPMNullAssertionID;
    IOReturn result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep,
        kIOPMAssertionLevelOn, CFSTR("This Is Not Free — Keep Awake"), &assertion);
    return result == kIOReturnSuccess ? assertion : kIOPMNullAssertionID;
}

void TNFKeepAwakeEnd(uint32_t assertion) {
    if (assertion != kIOPMNullAssertionID) IOPMAssertionRelease(assertion);
}
