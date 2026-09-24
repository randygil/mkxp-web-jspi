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
#include <mruby/array.h>

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

/* WEB PORT: HTTP for the HTTPLite shim. fetch() + AbortController timeout; under JSPI
 * the await suspends the wasm stack (like emscripten_sleep), so the call blocks the game
 * like mkxp-z's HTTPLite does on PC while the browser keeps running (Web Audio BGM, input).
 * Request/response bodies are raw bytes (ptr + length). Returns the HTTP status, or 0 on
 * a network error / CORS rejection / timeout (the error message is then the "body").
 * The response is kept in Module.__webHttp; the caller sizes buffers from the lengths and
 * copies it out with web_http_take_js. headersJson is a JSON object of header strings. */
EM_ASYNC_JS(int, web_http_js, (const char* methodC, const char* urlC, const char* headersC,
                               const char* bodyP, int bodyLen, int timeoutMs, int redirect,
                               int* outHdrLen, int* outBodyLen), {
	var method = UTF8ToString(methodC), url = UTF8ToString(urlC);
	var enc = new TextEncoder();
	var res = { status: 0, headers: new Uint8Array(0), body: new Uint8Array(0) };
	var fail = function(msg) { res.status = 0; res.headers = new Uint8Array(0); res.body = enc.encode(msg); };
	var ctl = (typeof AbortController !== "undefined") ? new AbortController() : null;
	var timer = null, timedOut = false;
	try {
		var hdrs = {};
		try { hdrs = JSON.parse(UTF8ToString(headersC) || "{}") || {}; } catch (e) {}
		var init = { method: method, headers: new Headers(), redirect: redirect ? "follow" : "manual",
		             cache: "no-store", credentials: "omit" };
		Object.keys(hdrs).forEach(function(k) {
			try { init.headers.append(k, String(hdrs[k])); } catch (e) {}
		});
		/* copy the body out of the heap BEFORE awaiting (memory may grow meanwhile) */
		if (method !== "GET" && method !== "HEAD") init.body = HEAPU8.slice(bodyP, bodyP + bodyLen);
		if (ctl) init.signal = ctl.signal;
		if (timeoutMs > 0) timer = setTimeout(function() { timedOut = true; if (ctl) ctl.abort(); }, timeoutMs);
		var r = await fetch(url, init);
		var body = new Uint8Array(await r.arrayBuffer());
		var lines = [];
		r.headers.forEach(function(v, k) { lines.push(k + ": " + v); });
		if (r.type === "opaqueredirect") {
			/* redirect = false: the browser hides the 3xx status and Location */
			res.status = 302; lines = ["x-web-opaque-redirect: 1"];
		} else {
			res.status = r.status || 0;
			if (!res.status) { fail("HTTP request failed (opaque response)"); }
		}
		if (res.status) { res.headers = enc.encode(lines.join(String.fromCharCode(10))); res.body = body; }
	} catch (e) {
		if (timedOut) fail("Request timed out after " + timeoutMs + " ms: " + url);
		else fail("Connection failed (network error or CORS rejected): " + url + " (" + (e && e.message || e) + ")");
	} finally {
		if (timer) clearTimeout(timer);
	}
	Module.__webHttp = res;
	HEAP32[outHdrLen >> 2] = res.headers.length;
	HEAP32[outBodyLen >> 2] = res.body.length;
	return res.status;
});

EM_JS(void, web_http_take_js, (char* hdrOut, char* bodyOut), {
	var res = Module.__webHttp;
	if (!res) return;
	if (res.headers.length) HEAPU8.set(res.headers, hdrOut);
	if (res.body.length) HEAPU8.set(res.body, bodyOut);
	Module.__webHttp = null;
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

/* WEB PORT: web_http(method, url, headers_json, body, timeout_ms, redirect)
 *   -> [status, "name: value\n..." response headers, body]
 * Binary-safe in both directions. status 0 = connection failure / CORS / timeout; the
 * third element is then the error message. Backs the HTTPLite shim (essentials_shim.rb). */
MRB_FUNCTION(kernelWebHttp)
{
	char *method, *url, *headers, *body;
	mrb_int bodyLen = 0, timeoutMs = 30000;
	mrb_bool redirect = 1;

	mrb_get_args(mrb, "zzzs|ib", &method, &url, &headers, &body, &bodyLen, &timeoutMs, &redirect);

#ifdef __EMSCRIPTEN__
	int hdrLen = 0, respLen = 0;
	int status = web_http_js(method, url, headers, body, (int) bodyLen, (int) timeoutMs,
	                         redirect ? 1 : 0, &hdrLen, &respLen);
	char *hdrBuf = (char*) malloc(hdrLen + 1);
	char *respBuf = (char*) malloc(respLen + 1);
	if (!hdrBuf || !respBuf)
	{
		free(hdrBuf);
		free(respBuf);
		mrb_raise(mrb, getMrbData(mrb)->exc[MKXP], "web_http: out of memory");
	}
	web_http_take_js(hdrBuf, respBuf);
	mrb_value vals[3];
	vals[0] = mrb_fixnum_value(status);
	vals[1] = mrb_str_new(mrb, hdrBuf, hdrLen);
	vals[2] = mrb_str_new(mrb, respBuf, respLen);
	free(hdrBuf);
	free(respBuf);
	return mrb_ary_new_from_values(mrb, 3, vals);
#else
	mrb_value vals[3] = { mrb_fixnum_value(0), mrb_str_new_cstr(mrb, ""),
	                      mrb_str_new_cstr(mrb, "web_http: not a web build") };
	return mrb_ary_new_from_values(mrb, 3, vals);
#endif
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
	mrb_define_module_function(mrb, module, "web_http", kernelWebHttp, MRB_ARGS_ARG(4, 2));
}
