/*
** kernel.cpp
**
** This file is part of mkxp.
**
** Copyright (C) 2013 Jonas Kulla <Nyocurio@gmail.com>
**
** mkxp is free software: you can redistribute it and/or modify
** it under the terms of the GNU General Public License as published by
** the Free Software Foundation, either version 2 of the License, or
** (at your option) any later version.
**
** mkxp is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
** GNU General Public License for more details.
**
** You should have received a copy of the GNU General Public License
** along with mkxp.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <mruby.h>
#include <mruby/string.h>
#include <mruby/compile.h>

#include <stdlib.h>
#include <sys/time.h>

#include <SDL_messagebox.h>

#include "../binding-util.h"
#include "marshal.h"
#include "file-helper.h"
#include "sharedstate.h"
#include "eventthread.h"
#include "exception.h"
#include "filesystem.h"
#include "binding.h"

#ifdef __EMSCRIPTEN__
#include "emscripten.hpp"
#include <emscripten.h>

/* WEB PORT: case-insensitive lookup of a game path in the asset mapping. Returns a
 * real-cased path ("Audio/BGM/Titulo.ogg") into out; returns 0 when nothing matches. */
EM_JS(int, web_resolve_path_js, (const char* pathC, char* out, int outLen), {
	var p = UTF8ToString(pathC).split(String.fromCharCode(92)).join("/").toLowerCase();
	if (p.indexOf("./") === 0) p = p.substring(2);
	if (typeof mapping === "undefined") return 0;
	var slash = p.lastIndexOf("/"), dot = p.lastIndexOf(".");
	var v = mapping[dot > slash ? p.substring(0, dot) : p];
	if (!v) return 0;
	v = v.split("?")[0];
	if (v.toLowerCase() !== p) return 0;
	stringToUTF8(v, out, outLen);
	return 1;
});

/* WEB PORT: mruby has no Dir. List a directory of the in-memory FS, entries joined by
 * '
' (incl. "." and ".."). Returns -1 if the path is not a readable directory, or the
 * byte length needed (if it exceeds outLen the caller retries with a bigger buffer). */
EM_JS(int, web_readdir_js, (const char* pathC, char* out, int outLen), {
	var list;
	try { list = FS.readdir(UTF8ToString(pathC)); } catch (e) { return -1; }
	var s = list.join(String.fromCharCode(10));
	var need = lengthBytesUTF8(s) + 1;
	if (need <= outLen) stringToUTF8(s, out, outLen);
	return need;
});

/* WEB PORT: text entry (Input.text_input= / Input.gets). js/textinput.js buffers typed
 * characters (physical keyboard, or the on-screen keyboard of a focused hidden <input>). */
EM_JS(void, web_text_input_js, (int on), {
	if (window.webTextInput) window.webTextInput(!!on);
});

EM_JS(int, web_text_gets_js, (char* out, int outLen), {
	var s = window.webTextGets ? window.webTextGets() : "";
	if (!s) return 0;
	stringToUTF8(s, out, outLen);
	return 1;
});

EM_JS(int, web_mkdir_js, (const char* pathC), {
	try { FS.mkdir(UTF8ToString(pathC)); return 1; } catch (e) { return 0; }
});
#endif

void mrbBindingTerminate();

MRB_FUNCTION(kernelLoadData)
{
	const char *filename;
	mrb_get_args(mrb, "z", &filename);

	mrb_value obj;
	try {
		SDL_rw_file_helper fileHelper;
		fileHelper.filename = filename;
		char * contents = fileHelper.read();
		mrb_value rawdata = mrb_str_new_static(mrb, contents, fileHelper.length);
		obj = mrb_marshal_load(mrb, rawdata);
	}
	catch (const Exception &e)
	{
		raiseMrbExc(mrb, e);
	}

	return obj;
}

MRB_FUNCTION(kernelSaveData)
{
	mrb_value obj;
	const char *filename;

	mrb_get_args(mrb, "oz", &obj, &filename);

	try {
		mrb_value dumped = mrb_nil_value();
		mrb_marshal_dump(mrb, obj, dumped);
		SDL_rw_file_helper fileHelper;
		fileHelper.filename = filename;
		fileHelper.write(RSTRING_PTR(dumped));
	}
	catch (const Exception &e)
	{
		raiseMrbExc(mrb, e);
	}

	return mrb_nil_value();
}

MRB_FUNCTION(kernelSaveAsync)
{
	mrb_value obj;
	const char *filename;

	mrb_get_args(mrb, "z", &filename);

#ifdef __EMSCRIPTEN__
	save_file_async_js(filename);

#endif
	return mrb_nil_value();
}

/* WEB PORT: make sure a game file is actually downloaded into the in-memory FS
 * (drive.js only writes 1-byte placeholders up front). Needed before reading it
 * with mruby-io File/IO, which bypasses the engine loader used by load_data. */
MRB_FUNCTION(kernelWebFetch)
{
	const char *filename;

	mrb_get_args(mrb, "z", &filename);

#ifdef __EMSCRIPTEN__
	load_file_async_js(filename);
#endif
	return mrb_nil_value();
}

MRB_FUNCTION(kernelWebResolvePath)
{
	const char *filename;

	mrb_get_args(mrb, "z", &filename);

#ifdef __EMSCRIPTEN__
	char buf[1024];
	if (web_resolve_path_js(filename, buf, sizeof(buf)))
		return mrb_str_new_cstr(mrb, buf);
#endif
	return mrb_nil_value();
}

MRB_FUNCTION(kernelWebReaddir)
{
	const char *path;

	mrb_get_args(mrb, "z", &path);

#ifdef __EMSCRIPTEN__
	int cap = 8192;
	for (int attempt = 0; attempt < 2; ++attempt)
	{
		char *buf = (char*) malloc(cap);
		int need = web_readdir_js(path, buf, cap);
		if (need < 0)
		{
			free(buf);
			return mrb_nil_value();
		}
		if (need <= cap)
		{
			mrb_value v = mrb_str_new_cstr(mrb, buf);
			free(buf);
			return v;
		}
		free(buf);
		cap = need;
	}
#endif
	return mrb_nil_value();
}

MRB_FUNCTION(kernelWebMkdir)
{
	const char *path;

	mrb_get_args(mrb, "z", &path);

#ifdef __EMSCRIPTEN__
	return mrb_bool_value(web_mkdir_js(path) != 0);
#else
	return mrb_false_value();
#endif
}

MRB_FUNCTION(kernelWebTextInput)
{
	mrb_bool on;

	mrb_get_args(mrb, "b", &on);

#ifdef __EMSCRIPTEN__
	web_text_input_js(on ? 1 : 0);
#endif
	return mrb_bool_value(on);
}

MRB_FUNCTION(kernelWebTextGets)
{
#ifdef __EMSCRIPTEN__
	char buf[512];
	if (web_text_gets_js(buf, sizeof(buf)))
		return mrb_str_new_cstr(mrb, buf);
#endif
	return mrb_str_new_cstr(mrb, "");
}

void kernelBindingInit(mrb_state *mrb)
{
	RClass *module = mrb->kernel_module;

	mrb_define_module_function(mrb, module, "load_data", kernelLoadData, MRB_ARGS_REQ(1));
	mrb_define_module_function(mrb, module, "save_data", kernelSaveData, MRB_ARGS_REQ(2));
	mrb_define_module_function(mrb, module, "save_file_async", kernelSaveAsync, MRB_ARGS_REQ(1));
	mrb_define_module_function(mrb, module, "web_fetch_file", kernelWebFetch, MRB_ARGS_REQ(1));
	mrb_define_module_function(mrb, module, "web_resolve_path", kernelWebResolvePath, MRB_ARGS_REQ(1));
	mrb_define_module_function(mrb, module, "web_readdir", kernelWebReaddir, MRB_ARGS_REQ(1));
	mrb_define_module_function(mrb, module, "web_mkdir", kernelWebMkdir, MRB_ARGS_REQ(1));
	mrb_define_module_function(mrb, module, "web_text_input", kernelWebTextInput, MRB_ARGS_REQ(1));
	mrb_define_module_function(mrb, module, "web_text_gets", kernelWebTextGets, MRB_ARGS_NONE());
}
