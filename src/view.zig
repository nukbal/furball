const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const model_mod = @import("model.zig");

const canvas = native_sdk.canvas;

pub const Model = model_mod.Model;
pub const Msg = model_mod.Msg;
pub const Ui = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");
pub const CompiledAppView = canvas.CompiledMarkupView(Model, Msg, app_markup);
pub const dev_markup_reload = builtin.mode == .Debug;

