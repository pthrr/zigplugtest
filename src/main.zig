const std = @import("std");

const c = @cImport({
    @cInclude("clap/clap.h");
    @cInclude("string.h");
});

// Plugin State
const LinearAmp = struct {
    host: *const c.clap_host_t,
    gain: f32,

    const PARAM_GAIN: c.clap_id = 0;
};

// Plugin descriptor
const features = [_:null]?[*:0]const u8{
    c.CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
    c.CLAP_PLUGIN_FEATURE_UTILITY
};

const descriptor = c.clap_plugin_descriptor_t{
    .clap_version = c.CLAP_VERSION,
    .id = "com.example.linear-amp",
    .name = "Linear Amplifier",
    .vendor = "Example Audio",
    .url = "https://example.com",
    .manual_url = "",
    .support_url = "",
    .version = "1.0.0",
    .description = "A simple linear amplifier plugin",
    .features = @ptrCast(&features),
};

// Plugin implementation
fn plugin_init(plugin: [*c]const c.clap_plugin_t) callconv(.C) bool {
    const plugin_mut = @as([*c]c.clap_plugin_t, @constCast(plugin));
    const amp = @as(*LinearAmp, @ptrCast(@alignCast(plugin_mut.*.plugin_data.?)));
    amp.gain = 1.0;
    return true;
}

fn plugin_destroy(plugin: [*c]const c.clap_plugin_t) callconv(.C) void {
    const plugin_mut = @as([*c]c.clap_plugin_t, @constCast(plugin));
    if (plugin_mut.*.plugin_data) |data| {
        const allocator = std.heap.c_allocator;
        const amp = @as(*LinearAmp, @ptrCast(@alignCast(data)));
        allocator.destroy(amp);
    }
}

fn plugin_activate(plugin: [*c]const c.clap_plugin_t, sample_rate: f64, min_frames_count: u32, max_frames_count: u32) callconv(.C) bool {
    _ = plugin;
    _ = sample_rate;
    _ = min_frames_count;
    _ = max_frames_count;
    return true;
}

fn plugin_deactivate(plugin: [*c]const c.clap_plugin_t) callconv(.C) void {
    _ = plugin;
}

fn plugin_start_processing(plugin: [*c]const c.clap_plugin_t) callconv(.C) bool {
    _ = plugin;
    return true;
}

fn plugin_stop_processing(plugin: [*c]const c.clap_plugin_t) callconv(.C) void {
    _ = plugin;
}

fn plugin_reset(plugin: [*c]const c.clap_plugin_t) callconv(.C) void {
    _ = plugin;
}

fn plugin_process(plugin: [*c]const c.clap_plugin_t, process: [*c]const c.clap_process_t) callconv(.C) c.clap_process_status {
    const plugin_mut = @as([*c]c.clap_plugin_t, @constCast(plugin));
    const amp = @as(*LinearAmp, @ptrCast(@alignCast(plugin_mut.*.plugin_data.?)));
    const proc = process.*;

    if (proc.audio_inputs_count == 0 or proc.audio_outputs_count == 0) {
        return c.CLAP_PROCESS_CONTINUE;
    }

    const input = &proc.audio_inputs[0];
    const output = &proc.audio_outputs[0];

    if (input.data32) |in_data| {
        if (output.data32) |out_data| {
            const channel_count = @min(input.channel_count, output.channel_count);

            for (0..channel_count) |ch| {
                for (0..proc.frames_count) |frame| {
                    out_data[ch][frame] = in_data[ch][frame] * amp.gain;
                }
            }
        }
    }

    return c.CLAP_PROCESS_CONTINUE;
}

fn plugin_get_extension(plugin: [*c]const c.clap_plugin_t, extension_id: [*c]const u8) callconv(.C) ?*const anyopaque {
    _ = plugin;

    const params_ext = "clap.params";
    if (c.strcmp(extension_id, params_ext.ptr) == 0) {
        return @ptrCast(&params_extension);
    }

    return null;
}

fn plugin_on_main_thread(plugin: [*c]const c.clap_plugin_t) callconv(.C) void {
    _ = plugin;
}

// Parameters extension
fn params_count(plugin: [*c]const c.clap_plugin_t) callconv(.C) u32 {
    _ = plugin;
    return 1; // Only gain parameter
}

fn params_get_info(plugin: [*c]const c.clap_plugin_t, param_index: u32, param_info: [*c]c.clap_param_info_t) callconv(.C) bool {
    _ = plugin;

    if (param_index != 0) return false;

    param_info.*.id = LinearAmp.PARAM_GAIN;
    param_info.*.flags = c.CLAP_PARAM_IS_AUTOMATABLE;
    param_info.*.cookie = null;
    param_info.*.min_value = 0.0;
    param_info.*.max_value = 2.0;
    param_info.*.default_value = 1.0;

    // Copy strings safely
    const name = "Gain";
    const module = "";
    @memcpy(param_info.*.name[0..name.len], name);
    param_info.*.name[name.len] = 0;
    @memcpy(param_info.*.module[0..module.len], module);
    param_info.*.module[module.len] = 0;

    return true;
}

fn params_get_value(plugin: [*c]const c.clap_plugin_t, param_id: c.clap_id, value: [*c]f64) callconv(.C) bool {
    const plugin_mut = @as([*c]c.clap_plugin_t, @constCast(plugin));
    const amp = @as(*const LinearAmp, @ptrCast(@alignCast(plugin_mut.*.plugin_data.?)));

    if (param_id == LinearAmp.PARAM_GAIN) {
        value.* = amp.gain;
        return true;
    }

    return false;
}

fn params_value_to_text(plugin: [*c]const c.clap_plugin_t, param_id: c.clap_id, value: f64, display: [*c]u8, size: u32) callconv(.C) bool {
    _ = plugin;

    if (param_id == LinearAmp.PARAM_GAIN) {
        const text = std.fmt.allocPrintZ(std.heap.c_allocator, "{d:.2}", .{value}) catch return false;
        defer std.heap.c_allocator.free(text);

        const copy_len = @min(text.len, size - 1);
        @memcpy(display[0..copy_len], text[0..copy_len]);
        display[copy_len] = 0;
        return true;
    }

    return false;
}

fn params_text_to_value(plugin: [*c]const c.clap_plugin_t, param_id: c.clap_id, display: [*c]const u8, value: [*c]f64) callconv(.C) bool {
    _ = plugin;

    if (param_id == LinearAmp.PARAM_GAIN) {
        const text = std.mem.span(display);
        value.* = std.fmt.parseFloat(f64, text) catch return false;
        return true;
    }

    return false;
}

fn params_flush(plugin: [*c]const c.clap_plugin_t, in_events: [*c]const c.clap_input_events_t, out_events: [*c]const c.clap_output_events_t) callconv(.C) void {
    _ = plugin;
    _ = in_events;
    _ = out_events;
}

const params_extension = c.clap_plugin_params_t{
    .count = params_count,
    .get_info = params_get_info,
    .get_value = params_get_value,
    .value_to_text = params_value_to_text,
    .text_to_value = params_text_to_value,
    .flush = params_flush,
};

// Plugin factory
export fn clap_create_plugin(host: [*c]const c.clap_host_t, plugin_id: [*c]const u8) [*c]c.clap_plugin_t {
    const plugin_id_str = "com.example.linear-amp";
    if (c.strcmp(plugin_id, plugin_id_str.ptr) != 0) {
        return null;
    }

    const allocator = std.heap.c_allocator;
    const amp = allocator.create(LinearAmp) catch return null;
    amp.* = LinearAmp{
        .host = host,
        .gain = 1.0,
    };

    const plugin = allocator.create(c.clap_plugin_t) catch {
        allocator.destroy(amp);
        return null;
    };

    plugin.* = c.clap_plugin_t{
        .desc = &descriptor,
        .plugin_data = amp,
        .init = plugin_init,
        .destroy = plugin_destroy,
        .activate = plugin_activate,
        .deactivate = plugin_deactivate,
        .start_processing = plugin_start_processing,
        .stop_processing = plugin_stop_processing,
        .reset = plugin_reset,
        .process = plugin_process,
        .get_extension = plugin_get_extension,
        .on_main_thread = plugin_on_main_thread,
    };

    return plugin;
}

export fn clap_get_plugin_count() u32 {
    return 1;
}

export fn clap_get_plugin_descriptor(index: u32) [*c]const c.clap_plugin_descriptor_t {
    if (index != 0) return null;
    return &descriptor;
}
