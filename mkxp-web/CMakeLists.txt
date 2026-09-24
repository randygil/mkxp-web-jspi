cmake_minimum_required(VERSION 2.8.11)
Project(mkxp)

## Setup options ##

option(SHARED_FLUID "Dynamically link fluidsynth at build time" OFF)
option(WORKDIR_CURRENT "Keep current directory on startup" OFF)
option(FORCE32 "Force 32bit compile on 64bit OS" OFF)
set(BINDING "MRUBY" CACHE STRING "The Binding Type (MRI, MRUBY, NULL)")
set(EXTERNAL_LIB_PATH "" CACHE PATH "External precompiled lib prefix")

## Misc setup ##

include(cmake/PrepUtils.cmake)

set(CMAKE_INCLUDE_CURRENT_DIR ON)

IF("${CMAKE_SYSTEM}" MATCHES "Linux")
	SET(LINUX ON)
ENDIF()

IF(WORKDIR_CURRENT)
	list(APPEND DEFINES
		WORKDIR_CURRENT
	)
ENDIF()

IF(FORCE32)
	if(APPLE)
		SET(CMAKE_OSX_ARCHITECTURES "i386")
	else()
		SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -m32")
		SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -m32")
	endif()
ENDIF()

set(CMAKE_OSX_DEPLOYMENT_TARGET 10.6)

IF(LINUX)
	if(CMAKE_SIZEOF_VOID_P MATCHES "8" AND NOT(FORCE32) )
		set(CMAKE_EXECUTABLE_SUFFIX ".bin.x86_64")
		set(BIN_RPATH "\$ORIGIN/lib64")
		set(LIB_PATH "lib64")
	else()
		set(CMAKE_EXECUTABLE_SUFFIX ".bin.x86")
		set(BIN_RPATH "\$ORIGIN/lib")
		set(LIB_PATH "lib")
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -D_FILE_OFFSET_BITS=64")
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_FILE_OFFSET_BITS=64")
	endif()
elseif(APPLE)
	SET(BIN_RPATH "@executable_path/../Frameworks")
	set(LIB_PATH "lib")
endif()

set(CMAKE_SKIP_BUILD_RPATH TRUE)
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH ${BIN_RPATH})
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH FALSE)

## Locate core libs ##

find_package(PkgConfig REQUIRED)

if (EXTERNAL_LIB_PATH)
	set(CMAKE_PREFIX_PATH ${EXTERNAL_LIB_PATH})

	if(EXISTS "${EXTERNAL_LIB_PATH}/${LIB_PATH}/pkgconfig/")
		SET(ENV{PKG_CONFIG_PATH} "${EXTERNAL_LIB_PATH}/${LIB_PATH}/pkgconfig/")
	endif()
	if(APPLE)
		set(PLATFORM_SHARED_LIBS
			libSDL2.dylib libSDL2_image-2.0.0.dylib libSDL2_ttf-2.0.0.dylib libSDL_sound-1.0.1.dylib
			libfreetype.6.dylib libsigc-2.0.0.dylib
			CACHE STRING "List of shared libraries that need to be copied into the OS X bundle")
		foreach(lib ${PLATFORM_SHARED_LIBS})
			if(EXISTS ${EXTERNAL_LIB_PATH}/lib/${lib})
				list(APPEND PLATFORM_COPY_LIBS
					${EXTERNAL_LIB_PATH}/lib/${lib}
				)
			endif()
		endforeach()
	endif()
endif()

#pkg_check_modules(VORBISFILE    REQUIRED vorbisfile)
#pkg_check_modules(SDL2          REQUIRED sdl2)
#pkg_check_modules(SDL2_TTF      REQUIRED SDL2_ttf)
#pkg_check_modules(SDL2_IMAGE    REQUIRED SDL2_image)
#find_package(OpenAL REQUIRED)
#find_package(ZLIB REQUIRED)

## Setup main source ##

set(MAIN_HEADERS
	src/quadarray.h
	src/audio.h
	src/binding.h
	src/bitmap.h
	src/disposable.h
	src/etc.h
	src/etc-internal.h
	src/eventthread.h
	src/flashable.h
	src/font.h
	src/input.h
	src/iniconfig.h
	src/plane.h
	src/scene.h
	src/sprite.h
	src/table.h
	src/texpool.h
	src/tilequad.h
	src/transform.h
	src/viewport.h
	src/window.h
	src/serializable.h
	src/shader.h
	src/glstate.h
	src/quad.h
	src/tilemap.h
	src/tilemap-common.h
	src/graphics.h
	src/gl-debug.h
	src/global-ibo.h
	src/exception.h
	src/filesystem.h
	src/serial-util.h
	src/intrulist.h
	src/binding.h
	src/gl-util.h
	src/util.h
	src/config.h
	src/settingsmenu.h
	src/keybindings.h
	src/tileatlas.h
	src/sharedstate.h
	src/al-util.h
	src/boost-hash.h
	src/debugwriter.h
	src/gl-fun.h
	src/gl-meta.h
	src/vertex.h
	src/soundemitter.h
	src/aldatasource.h
	src/alstream.h
	src/audiostream.h
	src/rgssad.h
	src/windowvx.h
	src/tilemapvx.h
	src/tileatlasvx.h
	src/sharedmidistate.h
	src/fluid-fun.h
	src/sdl-util.h
)

set(MAIN_SOURCE
	src/main.cpp
	src/audio.cpp
	src/bitmap.cpp
	src/emscripten.cpp
	src/eventthread.cpp
	src/filesystem.cpp
	src/font.cpp
	src/input.cpp
	src/iniconfig.cpp
	src/plane.cpp
	src/scene.cpp
	src/sprite.cpp
	src/table.cpp
	src/tilequad.cpp
	src/viewport.cpp
	src/window.cpp
	src/texpool.cpp
	src/shader.cpp
	src/glstate.cpp
	src/tilemap.cpp
	src/autotiles.cpp
	src/graphics.cpp
	src/gl-debug.cpp
	src/etc.cpp
	src/config.cpp
	src/settingsmenu.cpp
	src/keybindings.cpp
	src/tileatlas.cpp
	src/sharedstate.cpp
	src/gl-fun.cpp
	src/gl-meta.cpp
	src/vertex.cpp
	src/soundemitter.cpp
	src/sdlsoundsource.cpp
	src/alstream.cpp
	src/audiostream.cpp
	src/rgssad.cpp
	src/bundledfont.cpp
	src/vorbissource.cpp
	src/pcmsource.cpp
	src/windowvx.cpp
	src/tilemapvx.cpp
	src/tileatlasvx.cpp
	src/autotilesvx.cpp
	src/midisource.cpp
	src/fluid-fun.cpp
)

if(WIN32)
	list(APPEND MAIN_HEADERS windows/resource.h)
	list(APPEND MAIN_SOURCE windows/resource.rc)
endif()

source_group("MKXP Source" FILES ${MAIN_SOURCE} ${MAIN_HEADERS})

## Setup embedded source ##

set(EMBEDDED_INPUT
	shader/common.h
	shader/transSimple.frag
	shader/trans.frag
	shader/hue.frag
	shader/sprite.frag
	shader/plane.frag
	shader/gray.frag
	shader/bitmapBlit.frag
	shader/flatColor.frag
	shader/simple.frag
	shader/simpleColor.frag
	shader/simpleAlpha.frag
	shader/simpleAlphaUni.frag
	shader/flashMap.frag
	shader/minimal.vert
	shader/simple.vert
	shader/simpleColor.vert
	shader/sprite.vert
	shader/tilemap.vert
	shader/tilemapvx.vert
	shader/blur.frag
	shader/blurH.vert
	shader/blurV.vert
	shader/simpleMatrix.vert
	assets/liberation.ttf
	assets/icon.png
)

if (RGSS2)
	list(APPEND DEFINES
		RGSS2
	)
endif()

if (SHARED_FLUID)
	pkg_check_modules(FLUID REQUIRED fluidsynth)
	list(APPEND DEFINES
		SHARED_FLUID
	)
endif()

## Process Embeddeds ##

find_program(XXD_EXE xxd
	DOC "Location of the xxd executable"
)

macro(ProcessWithXXD outvar inputfile outdir)
	get_filename_component(basefile ${inputfile} NAME)
	set(outputfile ${outdir}/${basefile}.xxd)
	set_source_files_properties(${outputfile} PROPERTIES HEADER_ONLY TRUE)
	add_custom_command(
		OUTPUT ${outputfile}
		COMMAND ${XXD_EXE} -i ${inputfile} ${outputfile}
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		DEPENDS ${inputfile}
		COMMENT "Generating XXD for ${inputfile}"
	)
	list(APPEND ${outvar}
		${outputfile}
	)
endmacro()

file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/xxdhack)
include_directories(
	${CMAKE_CURRENT_BINARY_DIR}/xxdhack
)

foreach(item ${EMBEDDED_INPUT})
	ProcessWithXXD(EMBEDDED_SOURCE ${item} ${CMAKE_CURRENT_BINARY_DIR})
endforeach()

source_group("Embedded Source" FILES ${EMBEDDED_INPUT} ${EMBEDDED_SOURCE})

## Setup binding source ##

if (BINDING STREQUAL "MRI")
	set(MRIVERSION "2.1" CACHE STRING "Version of MRI to link with")
	list(APPEND DEFINES
		BINDING_MRI
	)
	set(BINDING_HEADERS
		binding-mri/binding-util.h
		binding-mri/binding-types.h
		binding-mri/serializable-binding.h
		binding-mri/disposable-binding.h
		binding-mri/sceneelement-binding.h
		binding-mri/viewportelement-binding.h
		binding-mri/flashable-binding.h
	)
	set(BINDING_SOURCE
		binding-mri/binding-mri.cpp
		binding-mri/binding-util.cpp
		binding-mri/table-binding.cpp
		binding-mri/etc-binding.cpp
		binding-mri/bitmap-binding.cpp
		binding-mri/font-binding.cpp
		binding-mri/graphics-binding.cpp
		binding-mri/input-binding.cpp
		binding-mri/sprite-binding.cpp
		binding-mri/viewport-binding.cpp
		binding-mri/plane-binding.cpp
		binding-mri/window-binding.cpp
		binding-mri/tilemap-binding.cpp
		binding-mri/audio-binding.cpp
		binding-mri/module_rpg.cpp
		binding-mri/filesystem-binding.cpp
		binding-mri/windowvx-binding.cpp
		binding-mri/tilemapvx-binding.cpp
	)
elseif(BINDING STREQUAL "MRUBY")
	list(APPEND DEFINES
		BINDING_MRUBY
	)
	set(BINDING_HEADERS
		binding-mruby/binding-util.h
		binding-mruby/disposable-binding.h
		binding-mruby/flashable-binding.h
		binding-mruby/binding-types.h
		binding-mruby/sceneelement-binding.h
		binding-mruby/viewportelement-binding.h
		binding-mruby/serializable-binding.h
		binding-mruby/mrb-ext/rwmem.h
	)
	set(BINDING_SOURCE
		binding-mruby/binding-mruby.cpp
		binding-mruby/binding-util.cpp
		binding-mruby/window-binding.cpp
		binding-mruby/windowvx-binding.cpp
		binding-mruby/bitmap-binding.cpp
		binding-mruby/sprite-binding.cpp
		binding-mruby/font-binding.cpp
		binding-mruby/viewport-binding.cpp
		binding-mruby/plane-binding.cpp
		binding-mruby/audio-binding.cpp
		binding-mruby/tilemap-binding.cpp
		binding-mruby/tilemapvx-binding.cpp
		binding-mruby/etc-binding.cpp
		binding-mruby/graphics-binding.cpp
		binding-mruby/input-binding.cpp
		binding-mruby/table-binding.cpp
		binding-mruby/mrb-ext/file-helper.cpp
		binding-mruby/mrb-ext/rwmem.cpp
		binding-mruby/mrb-ext/kernel.cpp
	)
elseif(BINDING STREQUAL "NULL")
	set(BINDING_SOURCE
		binding-null/binding-null.cpp
	)
else()
	message(FATAL_ERROR "Must choose a valid binding type.  MRI, MRUBY, or NULL")
endif()

source_group("Binding Source" FILES ${BINDING_SOURCE} ${BINDING_HEADERS})

## Setup main executable ##

if(APPLE)
	find_library(CARBON_LIBRARY Carbon)
	find_library(IOKIT_LIBRARY IOKit)
	mark_as_advanced(CARBON_LIBRARY IOKIT_LIBRARY)
	list(APPEND PLATFORM_LIBRARIES
		${CARBON_LIBRARY}
		${IOKIT_LIBRARY}
		"-liconv"
	)
endif()

link_directories(
	deps/libsigc++/sigc++/.libs
	deps/pixman/pixman/.libs
	deps/physfs
	deps/mruby/build/wasm32-unknown-gnu/lib

	${SDL2_LIBRARY_DIRS}
)

add_executable(${PROJECT_NAME} MACOSX_BUNDLE
	${MAIN_HEADERS}
	${MAIN_SOURCE}
	${BINDING_HEADERS}
	${BINDING_SOURCE}
	${EMBEDDED_SOURCE}
)

target_compile_definitions(${PROJECT_NAME} PRIVATE
	${DEFINES}
)
# WEB PORT: enable MP3 decoding (minimp3) automatically once the single-header
# library is vendored into src/minimp3_ex.h. Presence-gated so the engine still
# builds WAV/OGG-only when the header is absent.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/minimp3_ex.h")
	target_compile_definitions(${PROJECT_NAME} PRIVATE MKXP_HAVE_MINIMP3)
	message(STATUS "minimp3 found -> MP3 audio ENABLED")
else()
	message(STATUS "minimp3 NOT found -> MP3 audio DISABLED (WAV/OGG only)")
endif()
target_include_directories(${PROJECT_NAME} PRIVATE
	src
	windows
	deps/libsigc++
	deps/pixman/pixman
	deps/physfs/src
	deps/mruby/include

	${SDL2_INCLUDE_DIRS}
	${FLUID_INCLUDE_DIRS}
	${OPENAL_INCLUDE_DIR}
)

target_link_libraries(${PROJECT_NAME}
	sigc-2.0.a physfs.a pixman-1.a mruby.a

	${SDL2_LIBRARIES}
	${SDL2_IMAGE_LIBRARIES}
	${SDL2_TTF_LIBRARIES}
	${SDL_SOUND_LIBRARIES}
	${PHYSFS_LIBRARIES}
	${PIXMAN_LIBRARIES}
	${Boost_LIBRARIES}
	${VORBISFILE_LIBRARIES}
	${FLUID_LIBRARIES}
	${OPENAL_LIBRARY}
	${ZLIB_LIBRARY}

	${PLATFORM_LIBRARIES}
)

# ENGINE FIX: enable C++ exception catching (DISABLE_EXCEPTION_CATCHING=0) so mkxp's
# binding try/catch(Exception&) works AND mruby's longjmp-based raise/rescue is catchable.
# MUST be built together with libmruby.a compiled the same way (see extra/build_config.rb).
# + ASYNCIFY_STACK_SIZE 1MB (deep boot chains).
# PERF (WEB PORT): ASSERTIONS=0 (release; =1 adds per-boundary asyncify state checks
# and JS-glue validation on EVERY import/export — measurable whole-program cost) and
# GL_TRACK_ERRORS=0 (skip per-GL-call error recording in the WebGL glue; mkxp only
# reads GL errors in debugMode). Flip both back for debug builds.
# PERF (WEB PORT): LTO is applied to libmruby.a ONLY (see extra/build_config.rb) --
# the mruby VM is the hot path. We deliberately do NOT put -flto here: with -flto at
# the mkxp *link*, emscripten swaps in the bitcode system-lib variants (lto/libc.a),
# and a JS-library dep pulls libc's fileno in AFTER the LTO codegen pass -> wasm-ld
# "attempt to add bitcode file after LTO (fileno)". Linking mkxp natively against a
# bitcode libmruby.a still LTO-optimizes mruby internally (wasm-ld codegens+optimizes
# the bitcode members it pulls) without the bitcode-libc breakage. emcc still runs
# Binaryen wasm-opt at -O3 regardless. mkxp's own C++ is not the bottleneck (render
# ~1.7ms/frame), so mkxp-internal / mkxp<->mruby cross-inlining is a negligible loss.
# WEB PORT: debug-build toggle. Set env MKXP_WEB_DEBUG=1 (docker-build.sh --debug) to
# compile a diagnostics engine that turns the silent native crashes into PRINTED faults:
#   ASSERTIONS=2           -> runtime sanity checks + readable abort messages
#   SAFE_HEAP=1            -> trap out-of-bounds / misaligned / null load+store AT the access
#   STACK_OVERFLOW_CHECK=2 -> guard + named stack-overflow abort
# plus -g2 for function names in stack traces. Keeps -O3 so the bug still reproduces.
# Release (env unset) keeps ASSERTIONS=0 / SAFE_HEAP=0 / -g0 for size + speed.
# NOTE: test the VALUE, not just DEFINED — docker-build.sh passes -e MKXP_WEB_DEBUG="" for a
# release build, which *defines* the env var (empty), so DEFINED would wrongly pick debug.
IF(NOT "$ENV{MKXP_WEB_DEBUG}" STREQUAL "")
  MESSAGE(STATUS "*** MKXP_WEB_DEBUG: ASSERTIONS=2 SAFE_HEAP=1 STACK_OVERFLOW_CHECK=2 -g2 ***")
  SET(WEB_G "-g2")
  SET(WEB_SAFETY "-s ASSERTIONS=2 -s SAFE_HEAP=1 -s STACK_OVERFLOW_CHECK=2")
ELSEIF(NOT "$ENV{MKXP_WEB_PROFILE}" STREQUAL "")
  # Release speed, but keep wasm function names for DevTools / CDP CPU profiles.
  MESSAGE(STATUS "*** MKXP_WEB_PROFILE: --profiling-funcs ***")
  SET(WEB_G "--profiling-funcs")
  SET(WEB_SAFETY "-s ASSERTIONS=0 -s SAFE_HEAP=0")
ELSE()
  SET(WEB_G "-g0")
  SET(WEB_SAFETY "-s ASSERTIONS=0 -s SAFE_HEAP=0")
ENDIF()
# WEB PORT (perf): -msimd128 lets LLVM/Binaryen autovectorize the scalar pixel loops at -O3
# (hueChange, gradient fills, blends). Safe: JSPI already requires a very recent browser, where
# WASM SIMD is universally supported.
SET(EMS_FLAGS " -s USE_SDL=2 -s USE_SDL_IMAGE=2 -s USE_ZLIB=1 -s USE_OGG=1 -s USE_VORBIS=1 -s USE_SDL_TTF=2 --std=c++14 -O3 -msimd128 ${WEB_G} -fwasm-exceptions -s SUPPORT_LONGJMP=wasm")
# WEB PORT: JSPI (JavaScript Promise Integration) instead of ASYNCIFY. JSPI uses
# native WebAssembly stack switching in the VM (Chrome 126+/148 here) instead of
# Binaryen's whole-program code rewrite, removing ASYNCIFY's ~50% speed overhead.
# Needs emsdk >= 3.1.61 (standard JSPI API). The suspending points are
# emscripten_sleep() (auto) and load_file_async_js (now EM_ASYNC_JS).
# (Original: -s ASYNCIFY=1 -s ASYNCIFY_IMPORTS=["load_file_async_js"] -s ASYNCIFY_STACK_SIZE=1048576)
SET(ASYNCIFY "-s JSPI")
# WEB PORT: emscripten's default wasm stack dropped to 64KB in 3.1.27 (this pins 3.1.61).
# That is far too small for the recursive RGSS/mruby interpreter + a sideview battle system's
# action machine + the event interpreter, and JSPI keeps the WHOLE native call stack live across
# every emscripten_sleep suspend. Deep chains (map transfer + autorun events + scene stack)
# overflow 64KB -> with SAFE_HEAP=0 it silently smashes adjacent memory -> "random" native
# freezes/crashes. Restore a generous 8MB stack (the old ASYNCIFY build reserved 1MB just for
# its rewrite stack; native JSPI stacks go deeper). Cost: 8MB of the 256MB initial heap.
SET(STACK_FLAGS "-s STACK_SIZE=8388608")
SET(ERR_FLAGS " -Wno-undefined-var-template")

# WEB PORT: mruby is built with 64-bit mrb_int (extra/build_config.rb); headers must agree.
add_definitions(-DMRB_INT64 -DMRB_METHOD_CACHE -DMRB_METHOD_CACHE_SIZE=4096)
# RGSS version the engine is pinned to (src/config.cpp): 1 = XP (e.g. Pokemon Essentials), 2 = VX.
IF(NOT "$ENV{MKXP_RGSS_VERSION}" STREQUAL "")
  add_definitions(-DMKXP_RGSS_VERSION=$ENV{MKXP_RGSS_VERSION})
ENDIF()
SET(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${EMS_FLAGS} ${ERR_FLAGS} ${ASYNCIFY}")
SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${EMS_FLAGS} ${ERR_FLAGS} ${ASYNCIFY}")
SET(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${EMS_FLAGS} ${ASYNCIFY} ${STACK_FLAGS} -lopenal ${WEB_SAFETY} -s GL_TRACK_ERRORS=0 -s MINIFY_HTML=0 --shell-file extra/shell.html -s EMULATE_FUNCTION_POINTER_CASTS=0 -s ALLOW_MEMORY_GROWTH=1 -s INITIAL_MEMORY=268435456 -s MAXIMUM_MEMORY=2147483648 -s MAX_WEBGL_VERSION=2 -s EXPORTED_FUNCTIONS='[\"_main\",\"_reloadBitmap\",\"_web_set_scancode\",\"_web_get_scancode\",\"_web_set_mouse\",\"_web_binding_count\"]' -s EXPORTED_RUNTIME_METHODS='[\"ccall\",\"cwrap\",\"addRunDependency\",\"removeRunDependency\"]'")

set_target_properties(
    ${PROJECT_NAME}
    PROPERTIES
        OUTPUT_NAME "mkxp"
        SUFFIX ".html"
)

PostBuildMacBundle(${PROJECT_NAME} "" "${PLATFORM_COPY_LIBS}")
