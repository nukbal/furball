const builtin = @import("builtin");

const implementation = if (builtin.os.tag == .macos) struct {
    const MallocZone = opaque {};
    extern fn malloc_default_zone() *MallocZone;
    extern fn malloc_zone_pressure_relief(zone: *MallocZone, goal: usize) usize;

    fn releaseIdle() void {
        _ = malloc_zone_pressure_relief(malloc_default_zone(), 0);
    }
} else struct {
    fn releaseIdle() void {}
};

pub fn releaseIdle() void {
    implementation.releaseIdle();
}
