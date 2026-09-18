#ifndef HYPRTK_GCC14_COMPAT_HPP
#define HYPRTK_GCC14_COMPAT_HPP
// ── hyprtk GCC 14 libstdc++ compatibility ───────────────────────────────────
// The hyprwm 0.56 stack targets C++26, but Void's current toolchain is GCC 14.2
// whose libstdc++ predates a few C++23/26 library additions. This header
// supplies the ones that can be provided as free functions so the Hyprland
// source need not be patched for them. It is guarded by the standard
// feature-test macro, so it is a no-op on toolchains that already provide it
// (GCC 15+, where the real overload exists).
//
// Not covered here (must be source-patched): std::vector::append_range (a
// member function) and std::ranges::starts_with (a qualified call) — see
// hyprland-src-install.sh.
#include <string>
#include <string_view>
#include <utility>

// P2591R5: concatenation of basic_string and basic_string_view (C++26).
#if !defined(__cpp_lib_string_view) || __cpp_lib_string_view < 202403L
inline std::string operator+(const std::string& s, std::string_view sv) {
    std::string r(s);
    r.append(sv);
    return r;
}
inline std::string operator+(std::string&& s, std::string_view sv) {
    s.append(sv);
    return std::move(s);
}
inline std::string operator+(std::string_view sv, const std::string& s) {
    std::string r(sv);
    r.append(s);
    return r;
}
inline std::string operator+(std::string_view sv, std::string&& s) {
    std::string r(sv);
    r.append(s);
    return r;
}
#endif

#endif // HYPRTK_GCC14_COMPAT_HPP
