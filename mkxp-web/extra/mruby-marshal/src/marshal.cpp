// mruby-marshal (pulsejet/mruby-marshal @ d0b767b, MIT, by take-cheeze), vendored for
// mkxp-web with CRuby-compatibility fixes so savefiles are interchangeable with mkxp-z
// (CRuby 3.x on PC / Switch). Every change is marked "WEB PORT".
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/hash.h>
#include <mruby/khash.h>
#include <mruby/string.h>
#include <mruby/value.h>
#include <mruby/variable.h>
#include <mruby/marshal.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unordered_map>

#ifndef MRUBY_VERSION
#define mrb_module_get mrb_class_get
#define mrb_args_int int
#define mrb_symlen size_t
#else
#define mrb_args_int mrb_int
#define mrb_symlen mrb_int
#endif

#if MRUBY_RELEASE_MAJOR <= 1 && MRUBY_RELEASE_MINOR <= 2
typedef struct {
  mrb_value v;
  mrb_int n;
} mrb_hash_value;

KHASH_DECLARE(ht, mrb_value, mrb_hash_value, TRUE)
#endif

namespace {

enum { MAJOR_VERSION = 4, MINOR_VERSION = 8, };

// WEB PORT: CRuby writes Integers outside [-2**30, 2**30) as Bignum ('l'), on every
// platform. A wider 'i' is unreadable by CRuby on Windows (32-bit long: "long too big
// for this architecture") and misread above 2**31.
static const mrb_int FIXNUM_MARSHAL_MIN = -(static_cast<mrb_int>(1) << 30);
static const mrb_int FIXNUM_MARSHAL_MAX = (static_cast<mrb_int>(1) << 30) - 1;

// WEB PORT: CRuby tags every UTF-8 String with the ivar E=true; without it CRuby loads
// the string as ASCII-8BIT (Encoding::CompatibilityError as soon as a name with an
// accent meets a UTF-8 literal). mruby strings carry no encoding: treat any valid
// UTF-8 byte sequence as UTF-8, anything else as binary.
static bool valid_utf8(char const* s, mrb_int len) {
  unsigned char const* p = reinterpret_cast<unsigned char const*>(s);
  unsigned char const* e = p + len;
  while (p < e) {
    unsigned char c = *p;
    if (c < 0x80) { ++p; continue; }
    int n; uint32_t cp;
    if (c >= 0xC2 && c <= 0xDF) { n = 1; cp = c & 0x1F; }
    else if (c >= 0xE0 && c <= 0xEF) { n = 2; cp = c & 0x0F; }
    else if (c >= 0xF0 && c <= 0xF4) { n = 3; cp = c & 0x07; }
    else return false;
    if (e - p <= n) return false;
    for (int i = 1; i <= n; ++i) {
      if ((p[i] & 0xC0) != 0x80) return false;
      cp = (cp << 6) | (p[i] & 0x3F);
    }
    if ((n == 2 && cp < 0x800) || (n == 3 && (cp < 0x10000 || cp > 0x10FFFF)) ||
        (cp >= 0xD800 && cp <= 0xDFFF)) return false;
    p += n + 1;
  }
  return true;
}

static bool ascii_only(char const* s, mrb_int len) {
  for (mrb_int i = 0; i < len; ++i) { if (static_cast<unsigned char>(s[i]) >= 0x80) return false; }
  return true;
}

struct utility {
  utility(mrb_state* M)
      : M(M), regexp_class(mrb_class_get(M, "Regexp"))
      , symbols(mrb_ary_new(M)), objects(mrb_ary_new(M)) {}
  mrb_state* M;

  RClass* const regexp_class;
  mrb_value const symbols; // symbol table -> array
  mrb_value const objects; // object table -> array

  RClass* path2class(mrb_sym sym) const {
    mrb_int len;
    char const* begin = mrb_sym2name_len(M, sym, &len);
    return path2class(begin, len);
  }

  RClass* path2class(char const* path_begin, mrb_int len) const {
    char const* begin = path_begin;
    char const* p = begin;
    char const* end = begin + len;
    struct RClass* ret = M->object_class;

    while(true) {
      while((p < end and p[0] != ':') or
            ((p + 1) < end and p[1] != ':')) ++p;

      mrb_sym const cls = mrb_intern(M, begin, p - begin);
      if (!mrb_mod_cv_defined(M, ret, cls)) {
        mrb_raisef(M, mrb_class_get(M, "ArgumentError"), "undefined class/module %S",
                   mrb_str_new(M, path_begin, p - path_begin));
      }

      mrb_value const cnst = mrb_mod_cv_get(M, ret, cls);
      if (mrb_type(cnst) != MRB_TT_CLASS &&  mrb_type(cnst) != MRB_TT_MODULE) {
        mrb_raisef(M, mrb_class_get(M, "TypeError"), "%S does not refer to class/module",
                   mrb_str_new(M, path_begin, p - path_begin));
      }
      ret = mrb_class_ptr(cnst);

      if(p >= end) { break; }

      p += 2;
      begin = p;
    }
    return ret;
  }
};

template<class Out>
struct write_context : public utility {
  write_context(mrb_state *M, Out out) : utility(M), out_(out), n_objects(0) {}

  typedef Out out_type;
  out_type out_;

  // WEB PORT: hash lookups for links. The old linear scans made dumping O(n^2), and
  // compared mrb_values through mrb_cptr(), which for a Float is only the low 32 bits
  // of the double on wasm32: 0.2 and 0.4 (same mantissa) were written as the SAME
  // object, silently corrupting Float fields on the next load.
  std::unordered_map<uintptr_t, mrb_int> ptr_links;
  std::unordered_map<uint64_t, mrb_int> float_links;
  std::unordered_map<mrb_sym, mrb_int> sym_links;
  mrb_int n_objects;

  mrb_int find_link(mrb_value const& v) const {
    if (mrb_float_p(v)) {
      uint64_t bits; mrb_float f = mrb_float(v); memcpy(&bits, &f, sizeof(bits));
      auto it = float_links.find(bits);
      return it == float_links.end() ? -1 : it->second;
    }
    auto it = ptr_links.find(reinterpret_cast<uintptr_t>(mrb_ptr(v)));
    return it == ptr_links.end() ? -1 : it->second;
  }

  // Assigns the next object-table index (same numbering as CRuby's w_remember).
  void remember(mrb_value const& v) {
    mrb_ary_push(M, objects, v); // keeps it alive while dumping
    mrb_int const id = n_objects++;
    if (mrb_float_p(v)) {
      uint64_t bits; mrb_float f = mrb_float(v); memcpy(&bits, &f, sizeof(bits));
      float_links.emplace(bits, id);
    } else if (!mrb_fixnum_p(v)) {
      ptr_links.emplace(reinterpret_cast<uintptr_t>(mrb_ptr(v)), id);
    }
  }
  // An entry that can never be linked to (CRuby registers every Bignum it writes).
  void remember_unlinkable() { ++n_objects; }

  write_context& symbol(mrb_sym const sym) {
    auto it = sym_links.find(sym);
    if (it != sym_links.end()) { return tag(';').fixnum(it->second); } // symbol link

    mrb_symlen len;
    char const* const str = mrb_sym2name_len(M, sym, &len);
    mrb_int const id = RARRAY_LEN(symbols);
    mrb_ary_push(M, symbols, mrb_symbol_value(sym));
    sym_links.emplace(sym, id);
    // WEB PORT: non-ASCII symbols carry the encoding like CRuby's (I : ... E=true).
    if (!ascii_only(str, len) && valid_utf8(str, len)) {
      tag('I').tag(':').string(str, len);
      fixnum(1);
      symbol(mrb_intern_lit(M, "E"));
      return tag('T');
    }
    return tag(':').string(str, len);
  }

  write_context& version() {
    RClass* const mod = mrb_module_get(M, "Marshal");
    out_.byte(mrb_fixnum(mrb_mod_cv_get(M, mod, mrb_intern_lit(M, "MAJOR_VERSION"))));
    out_.byte(mrb_fixnum(mrb_mod_cv_get(M, mod, mrb_intern_lit(M, "MINOR_VERSION"))));
    return *this;
  }

  write_context& tag(char t) { out_.byte(t); return *this; }

  write_context& fixnum(mrb_int const v) {
    if(v == 0) { out_.byte(0); return *this; }
    else if(0 < v and v < 123) { out_.byte(v + 5); return *this; }
    else if(-124 < v and v < 0) { out_.byte((v - 5) & 0xff); return *this; }
    else {
      char buf[sizeof(mrb_int) + 1];
      mrb_int x = v;
      size_t i = 1;
      for(; i <= sizeof(mrb_int); ++i) {
        buf[i] = x & 0xff;
        x = x < 0 ? ~((~x) >> 8) : (x >> 8);
        if(x ==  0) { buf[0] =  i; break; }
        if(x == -1) { buf[0] = -i; break; }
      }
      out_.byte_array(buf, i + 1);
      return *this;
    }
  }

  // WEB PORT: CRuby's Bignum layout: 'l', sign, length in 16-bit words, magnitude (LE).
  write_context& bignum(mrb_int const v) {
    uint64_t mag = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
    char buf[8];
    size_t n = 0;
    while (mag) { buf[n++] = (char)(mag & 0xff); mag >>= 8; }
    if (n & 1) { buf[n++] = 0; }
    remember_unlinkable();
    tag('l').tag(v < 0 ? '-' : '+').fixnum((mrb_int)(n / 2));
    out_.byte_array(buf, n);
    return *this;
  }

  write_context& string(char const* str, size_t len) {
    fixnum(len);
    out_.byte_array(str, len);
    return *this;
  }
  write_context& string(char const* str)
  { return string(str, strlen(str)); }
  write_context& string(mrb_sym const sym) {
    mrb_symlen len;
    char const* const str = mrb_sym2name_len(M, sym, &len);
    return string(str, len);
  }
  write_context& string(mrb_value const& v)
  { return string(RSTRING_PTR(v), RSTRING_LEN(v)); }

  // WEB PORT: CRuby's Float text (w_float): "nan", "inf", "-inf", "0", "-0", else the
  // shortest decimal that reads back to the same double (was "%.16g": lossy).
  write_context& float_value(mrb_float const d) {
    char buf[64];
    if (isnan(d)) { strcpy(buf, "nan"); }
    else if (isinf(d)) { strcpy(buf, d < 0 ? "-inf" : "inf"); }
    else if (d == 0.0) { strcpy(buf, signbit(d) ? "-0" : "0"); }
    else {
      for (int prec = 1; prec <= 17; ++prec) {
        snprintf(buf, sizeof(buf), "%.*g", prec, (double)d);
        if (strtod(buf, NULL) == (double)d) break;
      }
      // "1e+300" / "1e-05" -> "1e300" / "1e-5", as CRuby writes them
      char* e = strchr(buf, 'e');
      if (e) {
        char* q = e + 1;
        if (*q == '+') { memmove(q, q + 1, strlen(q)); }
        else if (*q == '-') { ++q; }
        while (q[0] == '0' && q[1] != '\0') { memmove(q, q + 1, strlen(q)); }
      }
    }
    return tag('f').string(buf);
  }

  write_context& marshal(mrb_value const& v, mrb_int limit = -1);

  bool is_struct(mrb_value const& v) const {
    return mrb_class_defined(M, "Struct") and mrb_obj_is_kind_of(M, v, mrb_class_get(M, "Struct"));
  }

  write_context& link(int const l) {
    mrb_assert(l != -1);
    return tag('@').fixnum(l);
  }

  write_context& class_symbol(RClass* const v) {
    return symbol(mrb_intern_str(M, mrb_class_path(M, v)));
  }

  write_context& extended(mrb_value const& v, bool const check) {
    if(check) {} // check singleton

    RClass* cls = mrb_class(M, v);

    while(cls->tt == MRB_TT_ICLASS) {
      tag('e').symbol(mrb_intern_cstr(M, mrb_class_name(M, cls->c)));
      cls = cls->super;
    }
    return *this;
  }

  write_context& uclass(mrb_value const& v, RClass* const super) {
    extended(v, true);
    RClass* const real_class = mrb_class_real(mrb_class(M, v));
    if(real_class != super) { tag('C').class_symbol(real_class); }
    return *this;
  }

  write_context& klass(char t, mrb_value const& v, bool const check) {
    // TODO: compat table

    return extended(v, check).tag(t).class_symbol(mrb_class_real(mrb_class(M, v)));
  }

 private:
  struct hash_marshal_meta {
    write_context& ctx;
    mrb_int limit;
  };

  static int marshal_hash_each(mrb_state *mrb, mrb_value key, mrb_value val, void *meta_) {
    hash_marshal_meta *meta = (hash_marshal_meta*)meta_;
    meta->ctx.marshal(key, meta->limit).marshal(val, meta->limit);
    return 0;
  }

  struct ivar_marshal_meta {
    write_context& ctx;
    mrb_int limit;
  };

  static int marshal_ivar_each(mrb_state *mrb, mrb_value key, mrb_value val, void *meta_) {
    ivar_marshal_meta *meta = (ivar_marshal_meta*)meta_;
    mrb_sym const sym = mrb_symbol_p(key) ? mrb_symbol(key) : mrb_intern_str(mrb, mrb_obj_as_string(mrb, key));
    meta->ctx.symbol(sym).marshal(val, meta->limit);
    return 0;
  }
};

template<class Out>
write_context<Out>& write_context<Out>::marshal(mrb_value const& v, mrb_int limit) {
  if (limit == 0) { mrb_raise(M, mrb_class_get(M, "ArgumentError"), "depth limit"); }
  --limit;

  if(mrb_nil_p(v)) { return tag('0'); }

  // basic types without instance variables
  switch(mrb_vtype(mrb_type(v))) {
    case MRB_TT_FALSE: return tag('F');
    case MRB_TT_TRUE : return tag('T');
    case MRB_TT_FIXNUM: {
      mrb_int const i = mrb_fixnum(v);
      if (i < FIXNUM_MARSHAL_MIN || i > FIXNUM_MARSHAL_MAX) { return bignum(i); }
      return tag('i').fixnum(i);
    }
    case MRB_TT_SYMBOL: return symbol(mrb_symbol(v));

    default: break;
  }

  // check for link
  {
    mrb_int const l = find_link(v);
    if (l >= 0) return tag('@').fixnum(l);
  }

  RClass* const cls = mrb_obj_class(M, v);

  // check marshal_dump
  if(mrb_obj_respond_to(M, cls, mrb_intern_lit(M, "marshal_dump"))) {
    remember(v);
    // WEB PORT: marshal_dump takes no arguments (it was called with one).
    mrb_value const data = mrb_funcall(M, v, "marshal_dump", 0);
    return klass('U', v, false).marshal(data, limit);
  }
  // check _dump
  if(mrb_obj_respond_to(M, cls, mrb_intern_lit(M, "_dump"))) {
    mrb_value const data = mrb_funcall(M, v, "_dump", 1, mrb_fixnum_value(limit));
    if (!mrb_string_p(data)) {
      mrb_raise(M, mrb_class_get(M, "TypeError"), "_dump() must return string");
    }
    // WEB PORT: CRuby user-defined dumps carry the ivars of the _dump string (Time:
    // :offset, :zone, :nano_num, ...) as "I u <class> <bytes> <ivars>". mruby strings
    // can't hold ivars, so a class may supply them as a Hash through #_dump_ivars.
    mrb_value ivars = mrb_nil_value();
    if (mrb_obj_respond_to(M, cls, mrb_intern_lit(M, "_dump_ivars"))) {
      ivars = mrb_funcall(M, v, "_dump_ivars", 0);
      if (!mrb_hash_p(ivars) || mrb_hash_size(M, ivars) == 0) { ivars = mrb_nil_value(); }
    }
    if (!mrb_nil_p(ivars)) { tag('I'); }
    klass('u', v, false).string(data);
    if (!mrb_nil_p(ivars)) {
      fixnum(mrb_hash_size(M, ivars));
      auto meta = ivar_marshal_meta{*this, limit};
      mrb_hash_foreach(M, RHASH(ivars), &marshal_ivar_each, &meta);
    }
    // WEB PORT: registered AFTER its ivars, like CRuby (w_remember at the end), so the
    // link indices of everything that follows match.
    remember(v);
    return *this;
  }

  remember(v);

  mrb_value const iv_keys = mrb_obj_instance_variables(M, v);
  mrb_funcall(M, iv_keys, "sort!", 0);

  bool const utf8_str = mrb_string_p(v) && valid_utf8(RSTRING_PTR(v), RSTRING_LEN(v));
  mrb_int const n_ivars = RARRAY_LEN(iv_keys) + (utf8_str ? 1 : 0);

  if(mrb_type(v) != MRB_TT_OBJECT and cls != regexp_class and n_ivars > 0) { tag('I'); }

  if(cls == regexp_class) {
    uclass(v, regexp_class).tag('/').string(mrb_funcall(M, v, "source", 0));
    if(mrb_obj_respond_to(M, cls, mrb_intern_lit(M, "options"))) {
      out_.byte(mrb_fixnum(mrb_funcall(M, v, "options", 0)));
    } else { out_.byte(0); } // workaround
    return *this;
  } else if(is_struct(v)) {
    mrb_value const members = mrb_iv_get(M, mrb_obj_value(mrb_class(M, v)), mrb_intern_lit(M, "__members__"));
    klass('S', v, true).fixnum(RARRAY_LEN(members));
    for (mrb_int i = 0; i < RARRAY_LEN(members); ++i) {
      mrb_check_type(M, RARRAY_PTR(members)[i], MRB_TT_SYMBOL);
      symbol(mrb_symbol(RARRAY_PTR(members)[i])).marshal(RARRAY_PTR(v)[i], limit);
    }
  } else if(mrb_type(v) == MRB_TT_OBJECT) {
    klass('o', v, true).fixnum(RARRAY_LEN(iv_keys));
    for(int i = 0; i < RARRAY_LEN(iv_keys); ++i) {
      symbol(mrb_symbol(RARRAY_PTR(iv_keys)[i]))
          .marshal(mrb_iv_get(M, v, mrb_symbol(RARRAY_PTR(iv_keys)[i])), limit);
    }
    return *this;
  } else switch(mrb_vtype(mrb_type(v))) {
      // WEB PORT: the class/module itself (mrb_obj_class(v) is Class/Module).
      case MRB_TT_CLASS : return tag('c').string(mrb_class_path(M, mrb_class_ptr(v)));
      case MRB_TT_MODULE: return tag('m').string(mrb_class_path(M, mrb_class_ptr(v)));

      case MRB_TT_STRING:
        uclass(v, M->string_class).tag('"').string(v);
        break;

      case MRB_TT_FLOAT:
        float_value(mrb_float(v));
        break;

      case MRB_TT_ARRAY: {
        uclass(v, M->array_class).tag('[').fixnum(RARRAY_LEN(v));
        for(int i = 0; i < RARRAY_LEN(v); ++i) { marshal(RARRAY_PTR(v)[i], limit); }
      } break;

      case MRB_TT_HASH: {
        uclass(v, M->hash_class);

        // TODO: check proc default
        mrb_value const default_val = mrb_iv_get(M, v, mrb_intern_lit(M, "ifnone"));
        tag(mrb_nil_p(default_val)? '{' : '}');

#if MRUBY_RELEASE_MAJOR >= 2 && MRUBY_RELEASE_MINOR >= 1
        fixnum(mrb_hash_size(M, v));
        auto meta = hash_marshal_meta{*this, limit};
        mrb_hash_foreach(M, RHASH(v), &marshal_hash_each, &meta);
#elif MRUBY_RELEASE_MAJOR >= 2 && MRUBY_RELEASE_MINOR >= 0
        mrb_value const keys = mrb_hash_keys(M, v);
        mrb_funcall(M, keys, "sort!", 0);

        fixnum(RARRAY_LEN(keys));
        for(mrb_int i = 0; i < RARRAY_LEN(keys); ++i) {
          mrb_value const k = RARRAY_PTR(keys)[i];
          marshal(k, limit).marshal(mrb_hash_get(M, v, k), limit);
        }
#else
        khash_t(ht) const * const h = RHASH_TBL(v);

        fixnum(kh_size(h));
        for(khiter_t k = kh_begin(h); k != kh_end(h); ++k) {
          if (!kh_exist(h, k)) { continue; }
          marshal(kh_key(h, k), limit).marshal(kh_value(h, k).v, limit);
        }
#endif

        if(not mrb_nil_p(default_val)) { marshal(default_val, limit); }
      } break;

      case MRB_TT_DATA: {
        if(not mrb_obj_respond_to(M, cls, mrb_intern_lit(M, "_dump_data"))) {
          mrb_raise(M, mrb_class_get(M, "TypeError"), "_dump_data isn't defined'");
        }
        klass('d', v, true).marshal(mrb_funcall(M, v, "_dump_data", 0), limit);
      } break;


      default:
        mrb_raise(M, mrb_class_get(M, "TypeError"), "unsupported type");
        return *this;
    }

  // write instance variables (the encoding first, as CRuby's w_ivar does)
  if(n_ivars > 0) {
    fixnum(n_ivars);
    if (utf8_str) { symbol(mrb_intern_lit(M, "E")).tag('T'); }
    RObject* const obj = mrb_obj_ptr(v);
    for(int i = 0; i < RARRAY_LEN(iv_keys); ++i) {
      mrb_sym const key = mrb_symbol(RARRAY_PTR(iv_keys)[i]);
      symbol(key).marshal(mrb_obj_iv_get(M, obj, key), limit);
    }
  }
  return *this;
}

struct string_out {
  string_out(mrb_state* M, mrb_value const& str) : M(M), out(str) {}

  mrb_state * const M;
  mrb_value out;

  void byte(uint8_t const v) {
    char const buf[] = {static_cast<char>(v)};
    mrb_str_buf_cat(M, out, buf, 1);
  }

  void byte_array(char const *buf, size_t len) {
    mrb_str_buf_cat(M, out, buf, len);
  }
};

struct io_out {
  io_out(mrb_state* M, mrb_value const& out)
      : M(M), out(out), buf(mrb_str_new(M, NULL, 0)) {}

  mrb_state * const M;
  mrb_value const out, buf;

  void byte(uint8_t const v) {
    mrb_str_resize(M, buf, 1);
    RSTRING_PTR(buf)[0] = v;
    mrb_funcall(M, out, "write", 1, buf);
  }

  void byte_array(char const *ary, size_t len) {
    mrb_str_resize(M, buf, len);
    memcpy(RSTRING_PTR(buf), ary, len);
    mrb_funcall(M, out, "write", 1, buf);
  }
};

template<class In>
struct read_context : public utility {
  typedef In in_type;
  read_context(mrb_state* M, in_type in) : utility(M), in_(in) {}

  in_type in_;

  read_context& version() {
    uint8_t const major_version = in_.byte();
    uint8_t const minor_version = in_.byte();

    if (major_version != MAJOR_VERSION ||
        minor_version != MINOR_VERSION) {
      mrb_raisef(M, mrb_class_get(M, "TypeError"), "invalid marshal version: %S.%S (expected: %S.%S)",
                 mrb_fixnum_value(major_version), mrb_fixnum_value(minor_version),
                 mrb_fixnum_value(MAJOR_VERSION), mrb_fixnum_value(MINOR_VERSION));
    }

    return *this;
  }

  void number_too_big() {
    mrb_raise(M, mrb_class_get(M, "ArgumentError"), "marshal data too short / long too big");
  }

  mrb_int fixnum() {
    mrb_int const c = static_cast<signed char>(in_.byte());

    if(c == 0) return 0;
    else if(c > 0) {
      if(4 < c and c < 128) { return c - 5; }
      if(c > int(sizeof(mrb_int))) { number_too_big(); }
      mrb_int ret = 0;
      for(mrb_int i = 0; i < c; ++i) {
        ret |= static_cast<mrb_int>(in_.byte()) << (8*i);
      }
      return ret;
    }
    else {
      if(-129 < c and c < -4) { return c + 5; }
      mrb_int const len = -c;
      if(len > int(sizeof(mrb_int))) { number_too_big(); }
      mrb_int ret = ~0;
      for(mrb_int i = 0; i < len; ++i) {
        // WEB PORT: was `~(0xff << (8*i))` on an int: for i == 3 the mask sign-extended
        // wrongly and cleared the upper half, so negatives below -2**24 read as positive.
        ret &= ~(static_cast<mrb_int>(0xff) << (8*i));
        ret |= static_cast<mrb_int>(in_.byte()) << (8*i);
      }
      return ret;
    }
  }

  mrb_value string() { return in_.byte_array(fixnum()); }

  mrb_sym symbol() {
    switch(in_.byte()) {
      case ':': {
        mrb_sym const ret = mrb_intern_str(M, string());
        mrb_ary_push(M, symbols, mrb_symbol_value(ret));
        return ret;
      }
      case ';': { // get symbol from table
        mrb_int const id = fixnum();
        if (id < 0 || id >= RARRAY_LEN(symbols)) {
          mrb_raise(M, mrb_class_get(M, "ArgumentError"), "bad symbol");
        }
        return mrb_symbol(RARRAY_PTR(symbols)[id]);
      }
      case 'I': { // WEB PORT: symbol with an encoding (non-ASCII, from CRuby)
        mrb_sym const ret = symbol();
        mrb_int const len = fixnum();
        for (mrb_int i = 0; i < len; ++i) { symbol(); marshal(); }
        return ret;
      }
      default:
        mrb_raise(M, mrb_class_get(M, "ArgumentError"), "dump format error for symbol");
        return 0;
    }
  }

  void register_link(mrb_int id, mrb_value const& v) {
    mrb_ary_set(M, objects, id, v);
  }
  // WEB PORT: reserve the object-table slot before reading children (CRuby's r_entry
  // order); nil until the object exists.
  mrb_int reserve_link() {
    mrb_int const id = RARRAY_LEN(objects);
    mrb_ary_push(M, objects, mrb_nil_value());
    return id;
  }
  mrb_int push_link(mrb_value const& v) {
    mrb_int const id = RARRAY_LEN(objects);
    mrb_ary_push(M, objects, v);
    return id;
  }

  static bool encoding_ivar(mrb_state* M, mrb_sym key) {
    mrb_int key_len;
    char const* sym = mrb_sym2name_len(M, key, &key_len);
    return (key_len == 1 and sym[0] == 'E') or
           (key_len == 8 and memcmp(sym, "encoding", 8) == 0);
  }

  // 'u' : _dump / _load. `with_ivars`: it came as "I u ...", its ivars follow the
  // bytes. Registered after them (CRuby: r_entry after r_ivar + _load).
  mrb_value userdef(bool with_ivars) {
    mrb_sym const cls = symbol();
    RClass* const klass = path2class(cls);
    mrb_value const data = string();
    mrb_value ivars = mrb_nil_value();
    if (with_ivars) {
      mrb_int const len = fixnum();
      ivars = mrb_hash_new(M);
      int const ai = mrb_gc_arena_save(M);
      for (mrb_int i = 0; i < len; ++i) {
        mrb_sym const key = symbol();
        mrb_value const val = marshal();
        if (!encoding_ivar(M, key)) { mrb_hash_set(M, ivars, mrb_symbol_value(key), val); }
        mrb_gc_arena_restore(M, ai);
      }
      if (mrb_hash_size(M, ivars) == 0) { ivars = mrb_nil_value(); }
    }
    mrb_value const kv = mrb_obj_value(klass);
    mrb_value ret;
    if (!mrb_nil_p(ivars) && mrb_respond_to(M, kv, mrb_intern_lit(M, "_load_ivars"))) {
      ret = mrb_funcall(M, kv, "_load_ivars", 2, data, ivars);
    } else {
      ret = mrb_funcall(M, kv, "_load", 1, data);
    }
    push_link(ret);
    return ret;
  }

  mrb_value marshal();
  size_t consumed() const { return in_.consumed(); }
};

template<class In>
mrb_value read_context<In>::marshal() {
  char const tag = in_.byte();
  mrb_int const id = RARRAY_LEN(objects);

  mrb_value ret = mrb_nil_value();

  switch(tag) {
    case '0': return mrb_nil_value  (); // nil
    case 'T': return mrb_true_value (); // true
    case 'F': return mrb_false_value(); // false

    case 'i': // fixnum
      return mrb_fixnum_value(fixnum());

    case 'e': { // WEB PORT: extended (object.extend(Module))
      RClass* const mod = path2class(symbol());
      ret = marshal();
      mrb_funcall(M, ret, "extend", 1, mrb_obj_value(mod));
      return ret;
    }

    case ':': // symbol
    case ';': // symbol link
      in_.restore_byte(tag); // restore tag
      return mrb_symbol_value(symbol());

    case 'I': { // instance variable
      char const next = in_.byte();
      if (next == 'u') { return userdef(true); }
      in_.restore_byte(next);
      ret = marshal();
      size_t const len = fixnum();
      int const ai = mrb_gc_arena_save(M);
      for(size_t i = 0; i < len; ++i) {
        mrb_sym const key = symbol();
        mrb_value const val = marshal();
        if (!encoding_ivar(M, key)) { // TODO: store ignored encoding
          mrb_iv_set(M, ret, key, val);
        }
        mrb_gc_arena_restore(M, ai);
      }
      return ret;
    }

    case '@': {// link
      mrb_int const id = fixnum();
      if (id < 0 or id >= RARRAY_LEN(objects) or mrb_nil_p(RARRAY_PTR(objects)[id])) {
        mrb_raisef(M, mrb_class_get(M, "ArgumentError"), "Invalid link ID: %S (table size: %S)",
                   mrb_fixnum_value(id), mrb_fixnum_value(RARRAY_LEN(objects)));
      }
      return RARRAY_PTR(objects)[id];
    }

    case 'C': { // sub class instance variable of string, regexp, array, hash
      RClass* const klass = path2class(symbol());
      ret = marshal();
      mrb_basic_ptr(ret)->c = klass; // set class
      return ret;
    }

    case 'u': // _dump / _load defined class
      return userdef(false);

    case 'U': { // marshal_load / marshal_dump defined class
      RClass* const klass = path2class(symbol());
      mrb_int const slot = reserve_link();
      if (mrb_obj_respond_to(M, klass, mrb_intern_lit(M, "marshal_load"))) {
        // WEB PORT: CRuby allocates the object, registers it, then calls the INSTANCE
        // method marshal_load(data).
        ret = mrb_funcall(M, mrb_obj_value(klass), "allocate", 0);
        register_link(slot, ret);
        mrb_value const data = marshal();
        mrb_funcall(M, ret, "marshal_load", 1, data);
      } else {
        mrb_value const data = marshal();
        ret = mrb_funcall(M, mrb_obj_value(klass), "marshal_load", 1, data);
        register_link(slot, ret);
      }
      return ret;
    }

    case 'o': { // object
      ret = mrb_obj_value(mrb_obj_alloc(M, MRB_TT_OBJECT, path2class(symbol())));
      register_link(id, ret);
      size_t const len = fixnum();
      int const ai = mrb_gc_arena_save(M);
      for(size_t i = 0; i < len; ++i) {
        mrb_sym const key = symbol();
        mrb_iv_set(M, ret, key, marshal());
        mrb_gc_arena_restore(M, ai);
      }
      break;
    }

    case 'f': { // float
      mrb_value const str = string();
      register_link(id, ret = mrb_float_value(M, strtod(RSTRING_PTR(str), NULL)));
      break;
    }

    case 'l': { // WEB PORT: bignum (Integer if it fits in 64 bits, else Float)
      char const sign = in_.byte();
      mrb_int const shorts = fixnum();
      mrb_value const bytes = in_.byte_array(shorts * 2);
      unsigned char const* p = reinterpret_cast<unsigned char const*>(RSTRING_PTR(bytes));
      mrb_int n = RSTRING_LEN(bytes);
      while (n > 0 && p[n - 1] == 0) --n;
      if (n <= 8) {
        uint64_t mag = 0;
        for (mrb_int i = 0; i < n; ++i) mag |= (uint64_t)p[i] << (8 * i);
        if (sign == '-' ? mag <= ((uint64_t)1 << 63) : mag < ((uint64_t)1 << 63)) {
          ret = mrb_fixnum_value(sign == '-' ? (mrb_int)((uint64_t)0 - mag) : (mrb_int)mag);
        } else {
          ret = mrb_float_value(M, sign == '-' ? -(mrb_float)mag : (mrb_float)mag);
        }
      } else {
        mrb_float f = 0;
        for (mrb_int i = n - 1; i >= 0; --i) f = f * 256.0 + p[i];
        ret = mrb_float_value(M, sign == '-' ? -f : f);
      }
      register_link(id, ret);
      break;
    }

    case '"': register_link(id, ret = string()); break; // string

    case '/': { // regexp
      // TODO: check Regexp class is defined
      mrb_value args[] = { string(), mrb_fixnum_value(in_.byte()) };
      register_link(id, ret = mrb_funcall_argv(M, mrb_obj_value(mrb_class_get(M, "Regexp")),
                                               mrb_intern_lit(M, "new"), 2, args));
      break;
    }

    case '[': { // array
      size_t const len = fixnum();
      register_link(id, ret = mrb_ary_new_capa(M, len));
      int const ai = mrb_gc_arena_save(M);
      for(size_t i = 0; i < len; ++i) {
        mrb_ary_push(M, ret, marshal());
        mrb_gc_arena_restore(M, ai);
      }
      break;
    }

    case '{': // hash
    case '}': { // hash with default value
      size_t const len = fixnum();
      register_link(id, ret = mrb_hash_new_capa(M, len));
      int const ai = mrb_gc_arena_save(M);
      for(size_t i = 0; i < len; ++i) {
        mrb_value const key = marshal();
        mrb_hash_set(M, ret, key, marshal());
        mrb_gc_arena_restore(M, ai);
      }
      // set default value
      // WEB PORT: also flag the default (Hash#default ignores the bare "ifnone" ivar).
      if(tag == '}') {
        mrb_iv_set(M, ret, mrb_intern_lit(M, "ifnone"), marshal());
        RHASH(ret)->flags |= MRB_HASH_DEFAULT;
      }
      break;
    }

    case 'S': { // struct
      mrb_sym const cls_name = symbol();
      struct RClass *cls = path2class(cls_name);
      mrb_int const member_count = fixnum();
      // WEB PORT: the struct owns its slot before its members (was registered after,
      // on top of its first member's slot, shifting every later link).
      mrb_int const slot = reserve_link();

      mrb_value const struct_symbols = mrb_iv_get(M, mrb_obj_value(cls), mrb_intern_lit(M, "__members__"));
      mrb_check_type(M, struct_symbols, MRB_TT_ARRAY);
      if (member_count != RARRAY_LEN(struct_symbols)) {
        mrb_raisef(M, mrb_class_get(M, "TypeError"),
                   "struct %S not compatible (struct size differs)", mrb_symbol_value(cls_name));
      }

      mrb_value const symbols = mrb_ary_new_capa(M, member_count);
      mrb_value const values = mrb_ary_new_capa(M, member_count);

      int const ai = mrb_gc_arena_save(M);
      for (mrb_int i = 0; i < member_count; ++i) {
        mrb_ary_push(M, symbols, mrb_symbol_value(symbol()));
        mrb_ary_push(M, values, marshal());
        mrb_gc_arena_restore(M, ai);
      }

      for (mrb_int i = 0; i < member_count; ++i) {
        mrb_value src_sym = mrb_ary_ref(M, symbols, i);
        mrb_value dst_sym = mrb_ary_ref(M, struct_symbols, i);
        if (not mrb_obj_eq(M, src_sym, dst_sym)) {
          mrb_raisef(M, mrb_class_get(M, "TypeError"), "struct %S not compatible (:%S for :%S)",
                     mrb_symbol_value(cls_name), src_sym, dst_sym);
        }
      }

      ret = mrb_funcall_argv(M, mrb_obj_value(cls), mrb_intern_lit(M, "new"), member_count, RARRAY_PTR(values));
      register_link(slot, ret);
      break;
    }

    case 'M': // old format class/module
    case 'c': // class
    case 'm': {// module
      // check class or module
      // check class
      // check module
      mrb_value str = string();
      register_link(id, ret = mrb_obj_value(path2class(RSTRING_PTR(str), RSTRING_LEN(str))));
      break;
    }

    default:
      mrb_raisef(M, mrb_class_get(M, "TypeError"), "Unsupported marshal type: %S",
                 mrb_str_new(M, &tag, 1));
      return mrb_nil_value();
  }

  return ret;
}

struct string_in {
  string_in(mrb_state* M, char const* begin, size_t len)
      : M(M), begin(begin), end(begin + len), current(begin) {}

  mrb_state * const M;
  char const* const begin;
  char const* const end;
  char const* current;

  uint8_t byte() {
    if(current >= end) mrb_raise(M, mrb_class_get(M, "ArgumentError"), "marshal data too short");
    return *(current++);
  }

  void restore_byte(char) { --current; }

  mrb_value byte_array(size_t len) {
    if(len > static_cast<size_t>(end - current)) {
      mrb_raise(M, mrb_class_get(M, "ArgumentError"), "marshal data too short");
    }
    mrb_value const ret = mrb_str_new(M, current, len);
    current += len;
    return ret;
  }

  size_t consumed() const { return current - begin; }
};

struct io_in {
  io_in(mrb_state* M, mrb_value io)
      : M(M), io(io), buf(mrb_str_new(M, NULL, 0)), count(0) {}

  mrb_state * const M;
  mrb_value const io;
  mrb_value const buf;
  size_t count;

  uint8_t byte() {
    mrb_value const buf = mrb_funcall(M, io, "getc", 0);
    if (!mrb_string_p(buf) || RSTRING_LEN(buf) < 1) {
      mrb_raise(M, mrb_class_get(M, "ArgumentError"), "marshal data too short");
    }
    ++count;
    return RSTRING_PTR(buf)[0];
  }

  void restore_byte(char c) {
    mrb_funcall(M, io, "ungetc", 1, mrb_str_new(M, &c, 1));
    --count;
  }

  mrb_value byte_array(size_t len) {
    mrb_value const ret = mrb_funcall(M, io, "read", 1, mrb_fixnum_value(len));
    if(!mrb_string_p(ret) || static_cast<size_t>(RSTRING_LEN(ret)) < len) {
      mrb_raise(M, mrb_class_get(M, "ArgumentError"), "marshal data too short");
    }
    count += len;
    return ret;
  }

  size_t consumed() const { return count; }
};

mrb_value marshal_dump(mrb_state* M, mrb_value) {
  mrb_value obj, io = mrb_nil_value();
  mrb_int limit = -1;
  mrb_int const arg_count = mrb_get_args(M, "o|oi", &obj, &io, &limit);

  if (arg_count == 2 && mrb_fixnum_p(io)) {
    limit = mrb_fixnum(io);
    io = mrb_nil_value();
  }

  if (mrb_nil_p(io)) {
    mrb_value const str = mrb_str_new(M, NULL, 0);
    write_context<string_out>(M, string_out(M, str)).version().marshal(obj, limit);
    return str;
  } else {
    write_context<io_out>(M, io_out(M, io)).version().marshal(obj, limit);
    return io;
  }
}

mrb_value marshal_load(mrb_state* M, mrb_value) {
  mrb_value obj;
  mrb_get_args(M, "o", &obj);

  return mrb_string_p(obj)?
      read_context<string_in>(M, string_in(M, RSTRING_PTR(obj), RSTRING_LEN(obj))).version().marshal():
      read_context<io_in>(M, io_in(M, obj)).version().marshal();
}

// WEB PORT: Marshal.__load_partial(str) -> [obj, bytes_consumed]. Lets a caller load one
// object from a buffer holding several dumps back to back (a stream read in one go) and
// then reposition the stream, instead of the byte-per-funcall IO reader.
mrb_value marshal_load_partial(mrb_state* M, mrb_value) {
  mrb_value str;
  mrb_get_args(M, "S", &str);
  read_context<string_in> ctx(M, string_in(M, RSTRING_PTR(str), RSTRING_LEN(str)));
  mrb_value const obj = ctx.version().marshal();
  mrb_value const pair[] = { obj, mrb_fixnum_value((mrb_int)ctx.consumed()) };
  return mrb_ary_new_from_values(M, 2, pair);
}

}

extern "C" {

mrb_value mrb_marshal_dump(mrb_state* M, mrb_value obj, mrb_value io) {
  if (mrb_nil_p(io)) {
    mrb_value const str = mrb_str_new(M, NULL, 0);
    write_context<string_out>(M, string_out(M, str)).version().marshal(obj);
    return str;
  } else {
    write_context<io_out>(M, io_out(M, io)).version().marshal(obj);
    return io;
  }
}

mrb_value mrb_marshal_load(mrb_state* M, mrb_value obj) {
  return mrb_string_p(obj)?
      read_context<string_in>(M, string_in(M, RSTRING_PTR(obj), RSTRING_LEN(obj))).version().marshal():
      read_context<io_in>(M, io_in(M, obj)).version().marshal();
}

void mrb_mruby_marshal_gem_init(mrb_state* M) {
  RClass* const mod = mrb_define_module(M, "Marshal");

  mrb_define_module_function(M, mod, "load", &marshal_load, MRB_ARGS_REQ(1));
  mrb_define_module_function(M, mod, "restore", &marshal_load, MRB_ARGS_REQ(1));
  mrb_define_module_function(M, mod, "dump", &marshal_dump, MRB_ARGS_REQ(1));
  mrb_define_module_function(M, mod, "__load_partial", &marshal_load_partial, MRB_ARGS_REQ(1));

  mrb_define_const(M, mod, "MAJOR_VERSION", mrb_fixnum_value(MAJOR_VERSION));
  mrb_define_const(M, mod, "MINOR_VERSION", mrb_fixnum_value(MINOR_VERSION));
}

void mrb_mruby_marshal_gem_final(mrb_state*) {}

}
