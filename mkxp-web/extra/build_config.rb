MRuby::Build.new do |conf|
    toolchain :gcc
    conf.gembox 'default'
    # WEB PORT: 64-bit Integer (see the cross build below); keep host mrbc consistent.
    conf.cc.defines << 'MRB_INT64'
end

MRuby::CrossBuild.new('wasm32-unknown-gnu') do |conf|
    toolchain :clang
  
    conf.gembox 'default'
    # Pin mruby-onig-regexp (a transitive dep of pulsejet/mruby-marshal) to the
    # commit that was `master` when mkxp-web last built (Apr 2023). Newer master
    # (2025+) adds `#include <mruby/presym.h>`, which does not exist in mruby 2.1.2
    # and breaks the build. Declared BEFORE marshal so its add_dependency resolves
    # to this pinned commit instead of re-cloning master.
    conf.gem :github => 'mattn/mruby-onig-regexp', :checksum_hash => '074325207f9181ad242ffb8de34072607164f57f'
    # WEB PORT: pulsejet/mruby-marshal, vendored in extra/mruby-marshal with CRuby-format
    # fixes (Bignum, Float, String encoding, Time ivars, link order) so savefiles are
    # interchangeable with mkxp-z. See the WEB PORT notes in its src/marshal.cpp.
    conf.gem "#{MRUBY_ROOT}/../../extra/mruby-marshal"
    conf.gem :github => 'monochromegane/mruby-time-strftime'
    conf.gem :core => 'mruby-eval'
    conf.cc.command = 'emcc'
    # WEB PORT: enable C++ exception catching so it matches mkxp's build. Without
    # this, libmruby.a's setjmp landing pads are compiled out and mruby's own
    # longjmp-based raise/rescue can't be caught when mkxp enables exceptions,
    # surfacing as "Uncaught int". Must be consistent across mruby + mkxp.
    # WEB PORT (JSPI): full wasm-native EH. -fwasm-exceptions (native wasm exception
    # handling) + SUPPORT_LONGJMP=wasm (native wasm setjmp/longjmp for mruby's
    # raise/rescue). Replaces emscripten-mode (-sDISABLE_EXCEPTION_CATCHING=0 +
    # ASYNCIFY-based setjmp), which is incompatible with JSPI's native stack
    # switching ("undefined symbol: saveSetjmp"). emcc rejects wasm-longjmp mixed
    # with emscripten-EH, so both must be wasm-mode. Must match mkxp's link flags.
    # WEB PORT PERF: -flto (link-time optimization). Compiles mruby's C sources to
    # LLVM bitcode so the final emcc link can inline/optimize across the whole VM +
    # mkxp together (opcode dispatch, hot helpers). emar/llvm-ar handle bitcode
    # archives fine. Must match mkxp's link flags (CMakeLists EMS_FLAGS also gets -flto).
    conf.cc.flags = %W(-O3 -g0 -flto -fwasm-exceptions -sSUPPORT_LONGJMP=wasm)
    conf.cxx.command = 'em++'
    conf.cxx.flags = %W(-O3 -g0 -flto -std=c++14 -fwasm-exceptions -sSUPPORT_LONGJMP=wasm)

    # WEB PORT: 64-bit Integer. On wasm32 mruby defaults to 32-bit mrb_int, so any value
    # >= 2**31 silently becomes a Float (Pokémon Essentials trainer IDs are 32-bit
    # unsigned -> "expected Integer, got Float"). MUST match mkxp (CMakeLists -DMRB_INT64).
    conf.cc.defines << 'MRB_INT64'
    conf.cxx.defines << 'MRB_INT64'
    # WEB PORT PERF: global method cache (off by default in 2.1.2). Big games (Essentials
    # + dozens of plugins = deep alias chains / ancestors) otherwise walk the class chain
    # with a khash lookup per class on EVERY call. Changes mrb_state layout -> MUST match
    # mkxp (CMakeLists add_definitions).
    conf.cc.defines += %w(MRB_METHOD_CACHE MRB_METHOD_CACHE_SIZE=4096)
    conf.cxx.defines += %w(MRB_METHOD_CACHE MRB_METHOD_CACHE_SIZE=4096)

    conf.linker.command = 'emcc'
    conf.archiver.command = 'emar'
end
