-- ── Nvidia Environment Variables ──────────────────────
-- by Kori Tk (2026)
-- ─────────────────────────────────────────────────────
-- OPT-IN: Uncomment these lines ONLY if you have an Nvidia GPU.
-- These env vars are harmful on AMD/Intel systems.

--[[
hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
hl.env("__NV_PRIME_RENDER_OFFLOAD_PROVIDER", "NVIDIA-G0")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("__VK_LAYER_NV_optimus", "NVIDIA_only")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
]]
