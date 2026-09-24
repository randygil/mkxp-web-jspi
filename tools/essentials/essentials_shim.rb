#==============================================================================
# mkxp-z API shim for Pokemon Essentials v20/v21 games on mkxp-web/mruby.
# Appended to rgss.rb (after extra/rgss.rb) by pack.sh, so it runs before any game script.
# pack.sh prepends WEB_GAME_TITLE / WEB_USER_LANGUAGE (env GAME_TITLE / USER_LANGUAGE).
#==============================================================================

module System
  VERSION = "2.4.2/d13f35c" unless const_defined?(:VERSION)
  @__t0 = Time.now.to_f
  @__title = Object.const_defined?(:WEB_GAME_TITLE) ? WEB_GAME_TITLE : "RGSS-Web"

  def self.uptime;           Time.now.to_f - @__t0; end
  def self.delta;            (Time.now.to_f * 1_000_000).to_i; end
  def self.platform;         "Web"; end
  def self.is_windows?;      false; end
  def self.is_really_windows?; false; end
  def self.is_mac?;          false; end
  def self.is_linux?;        false; end
  def self.user_language;    Object.const_defined?(:WEB_USER_LANGUAGE) ? WEB_USER_LANGUAGE : "en_US"; end
  def self.user_name;        "Player"; end
  def self.game_title;       @__title; end
  def self.set_window_title(s); @__title = s.to_s; nil; end
  def self.window_title;     @__title; end
  def self.window_title=(s); @__title = s.to_s; end
  def self.data_directory;   "."; end
  def self.reload_cache;     nil; end
  def self.mount(*a);        nil; end
  def self.unmount(*a);      nil; end
  def self.launch(*a);       nil; end
  def self.puts(*a);         Kernel.puts(*a); end
  def self.raw_key_states;   nil; end
  def self.desensitize(*a);  nil; end
  def self.nproc;            1; end
  def self.memory;           256; end
  def self.default_font_family=(v); end
end

# NOTE: the engine defines MKXP = true; reopening it as a module crashes the VM.

# `defined?(A::B)` replacement (build_scripts.rb rewrites the keyword to this).
module Kernel
  def __defc(path)
    mod = Object
    path.split("::").each do |n|
      return nil unless mod.is_a?(Module) && mod.const_defined?(n.to_sym)
      mod = mod.const_get(n.to_sym)
    end
    "constant"
  end
end

module Encoding
  # encoding "objects": compare equal to their name and respond to #name
  class Name < String
    def name; to_s; end
    def to_s; String.new(self); end
  end
  UTF_8 = Name.new("UTF-8") unless const_defined?(:UTF_8)
  ASCII_8BIT = Name.new("ASCII-8BIT") unless const_defined?(:ASCII_8BIT)
  BINARY = ASCII_8BIT unless const_defined?(:BINARY)
  class << self
    attr_accessor :default_internal, :default_external
    def find(n); n; end
  end
end unless Object.const_defined?(:Encoding)

module Graphics
  class << self
    def scale;            1.0; end
    def scale=(v);        end
    def center;           nil; end
    def average_frame_rate; frame_rate; end
    def delta;            1.0 / frame_rate; end
    def screenshot(*a);   nil; end
    def frame_rate=(v);   end unless method_defined?(:frame_rate=)
  end
end

module Input
  # mkxp-z extended key API (SDL scancode names / symbols). Edge-detected per
  # Input.update from the harness' raw scancode table (Input.web_scancode?).
  SCANCODE = {
    :A => 4, :B => 5, :C => 6, :D => 7, :E => 8, :F => 9, :G => 10, :H => 11,
    :I => 12, :J => 13, :K => 14, :L => 15, :M => 16, :N => 17, :O => 18,
    :P => 19, :Q => 20, :R => 21, :S => 22, :T => 23, :U => 24, :V => 25,
    :W => 26, :X => 27, :Y => 28, :Z => 29,
    :N1 => 30, :N2 => 31, :N3 => 32, :N4 => 33, :N5 => 34, :N6 => 35,
    :N7 => 36, :N8 => 37, :N9 => 38, :N0 => 39,
    :RETURN => 40, :ENTER => 40, :ESCAPE => 41, :BACKSPACE => 42, :TAB => 43,
    :SPACE => 44, :MINUS => 45, :EQUALS => 46,
    :F1 => 58, :F2 => 59, :F3 => 60, :F4 => 61, :F5 => 62, :F6 => 63,
    :F7 => 64, :F8 => 65, :F9 => 66, :F10 => 67, :F11 => 68, :F12 => 69,
    :RIGHT => 79, :LEFT => 80, :DOWN => 81, :UP => 82,
    :LCTRL => 224, :LSHIFT => 225, :LALT => 226, :RCTRL => 228, :RSHIFT => 229, :RALT => 230,
    :CTRL => 224, :SHIFT => 225, :ALT => 226
  }
  # Windows virtual-key codes (older Essentials code) -> scancodes
  VK = { 0x08 => 42, 0x09 => 43, 0x0D => 40, 0x10 => 225, 0x11 => 224, 0x12 => 226,
         0x1B => 41, 0x20 => 44, 0x25 => 80, 0x26 => 82, 0x27 => 79, 0x28 => 81 }
  (0x41..0x5A).each { |c| VK[c] = 4 + (c - 0x41) }
  (0x30..0x39).each { |c| VK[c] = c == 0x30 ? 39 : 30 + (c - 0x31) }
  (0x70..0x7B).each { |c| VK[c] = 58 + (c - 0x70) }

  MOUSELEFT = 1001 unless const_defined?(:MOUSELEFT)
  MOUSERIGHT = 1002 unless const_defined?(:MOUSERIGHT)
  MOUSEMIDDLE = 1003 unless const_defined?(:MOUSEMIDDLE)
  F8 = 1008 unless const_defined?(:F8)
  F9 = 1009 unless const_defined?(:F9)
  F5 = 1005 unless const_defined?(:F5)
  CTRL = 1010 unless const_defined?(:CTRL)
  SHIFT = 1011 unless const_defined?(:SHIFT)
  ALT = 1012 unless const_defined?(:ALT)

  @__ex_prev = {}
  @__ex_cur = {}
  @__ex_cnt = {}

  class << self
    attr_reader :text_input
    # Typed text comes from js/textinput.js (keyboard, or the phone's on-screen keyboard).
    def text_input=(v)
      @text_input = v ? true : false
      (web_text_input(@text_input) rescue nil)
      v
    end
    def __sc(k)
      return VK[k] if k.is_a?(Integer)
      SCANCODE[k.to_s.upcase.to_sym]
    end
    def __exdown(sc)
      sc && respond_to?(:web_scancode?) ? web_scancode?(sc) : false
    end
    def __track(k)
      sc = __sc(k)
      unless @__ex_cur.key?(sc)
        @__ex_cur[sc] = __exdown(sc)
        @__ex_prev[sc] = @__ex_cur[sc]
        @__ex_cnt[sc] = 0
      end
      sc
    end
    alias_method :__mkxpweb_update, :update unless method_defined?(:__mkxpweb_update)
    def update
      __mkxpweb_update
      @__ex_cur.keys.each do |sc|
        @__ex_prev[sc] = @__ex_cur[sc]
        @__ex_cur[sc] = __exdown(sc)
        @__ex_cnt[sc] = @__ex_cur[sc] ? @__ex_cnt[sc] + 1 : 0
      end
      nil
    end
    def pressex?(k);   sc = __track(k); !!@__ex_cur[sc]; end
    def triggerex?(k); sc = __track(k); !!(@__ex_cur[sc] && !@__ex_prev[sc]); end
    def releaseex?(k); sc = __track(k); !!(!@__ex_cur[sc] && @__ex_prev[sc]); end
    def repeatex?(k)
      sc = __track(k)
      c = @__ex_cnt[sc]
      triggerex?(k) || (c >= 24 && (c - 24) % 6 == 0)
    end
    def release?(b);   false; end
    def time?(b);      0.0; end
    def count(b);      0; end
    def mouse_in_window; true; end
    def mouse_in_window?; true; end
    def scroll_v;      0; end
    def clipboard;     ""; end
    def clipboard=(v); end
    def gets;          (web_text_gets rescue ""); end
    def raw_key_states; nil; end
  end
end

class Bitmap
  def self.max_size; 16384; end unless respond_to?(:max_size)
  def mega?; width > 16384 || height > 16384; end unless method_defined?(:mega?)
end

class String
  # mruby's each_byte is built on #bytes; plugins that redefine #bytes on top of
  # each_byte (Luka's Scripting Utilities) then recurse forever (SystemStackError).
  def each_byte(&block)
    return to_enum(:each_byte) unless block
    i = 0
    n = bytesize
    while i < n
      block.call(getbyte(i))
      i += 1
    end
    self
  end
  def force_encoding(*a); self; end unless method_defined?(:force_encoding)
  def encoding; Encoding::UTF_8; end unless method_defined?(:encoding)
  def encode(*a); dup; end unless method_defined?(:encode)
  def valid_encoding?; true; end unless method_defined?(:valid_encoding?)
  def unicode_normalize(*a); self; end unless method_defined?(:unicode_normalize)
  def scrub(*a); self; end unless method_defined?(:scrub)
  def b; self; end unless method_defined?(:b)
end

# mruby has no Dir: back it with the browser FS (web_readdir / web_mkdir natives).
class Dir
  class << self
    def __ls(path)
      p = path.to_s
      p = "." if p.empty?
      r = (web_readdir(p) rescue nil)
      r = (web_readdir(__web_ci(p)) rescue nil) if r.nil?
      r && r.split("\n")
    end
    def entries(path, *a)
      l = __ls(path) or raise Errno::ENOENT, path.to_s
      l
    end
    def children(path, *a); entries(path) - [".", ".."]; end
    def each_child(path, *a, &b); children(path).each(&b); end
    def foreach(path, *a, &b); entries(path).each(&b); end
    def exist?(path); !__ls(path).nil?; end
    alias_method :exists?, :exist?
    def empty?(path); children(path).empty?; end
    def mkdir(path, *a); web_mkdir(path.to_s); 0; end
    def delete(*a); 0; end
    def rmdir(*a); 0; end
    def unlink(*a); 0; end
    def home(*a); "."; end
    def pwd; "."; end
    def chdir(*a); yield(a[0]) if block_given?; 0; end
    def __glob_re(seg)
      r = ""
      i = 0
      while i < seg.size
        c = seg[i]
        case c
        when "*" then r << "[^/]*"
        when "?" then r << "[^/]"
        when "{" then r << "(?:"
        when "}" then r << ")"
        when "," then r << (r.include?("(?:") ? "|" : ",")
        when "[", "]", "-" then r << c
        else r << Regexp.escape(c)
        end
        i += 1
      end
      Regexp.new('\A' + r + '\z', Regexp::IGNORECASE)
    end
    def __glob_walk(base, segs, out)
      if segs.empty?
        out << base
        return
      end
      seg, rest = segs[0], segs[1..-1]
      dir = base.empty? ? "." : base
      join = lambda { |n| base.empty? ? n : (base.end_with?("/") ? base + n : base + "/" + n) }
      if seg == "**"
        __glob_walk(base, rest, out)
        (children(dir) rescue []).each do |n|
          sub = join.call(n)
          __glob_walk(sub, segs, out) if FileTest.directory?(sub)
        end
      elsif seg =~ /[*?\[{]/
        re = __glob_re(seg)
        (children(dir) rescue []).each do |n|
          next if n.start_with?(".") && !seg.start_with?(".")
          __glob_walk(join.call(n), rest, out) if n =~ re
        end
      else
        nxt = join.call(seg)
        __glob_walk(nxt, rest, out) if rest.empty? ? FileTest.exist?(nxt) : FileTest.directory?(nxt)
      end
    end
    def glob(pattern, *a, &blk)
      out = []
      Array(pattern).each do |pat|
        pat = pat.to_s.gsub("\\", "/")
        base = pat.start_with?("/") ? "/" : ""
        __glob_walk(base, pat.split("/").reject(&:empty?), out)
      end
      out.uniq!
      blk ? (out.each(&blk); nil) : out
    end
    def [](*pats); glob(pats); end
  end
end

# Deleting a save must also drop it from IndexedDB, or it is restored on the next boot
# (drive.js saveFile removes the stored copy when the file no longer exists).
class << File
  alias_method :__web_delete, :delete unless method_defined?(:__web_delete)
  def delete(*paths)
    r = __web_delete(*paths)
    paths.each { |pth| (save_file_async(pth.to_s.sub(/\A\.\//, "")) rescue nil) }
    r
  end
  alias_method :unlink, :delete
end

class Numeric
  def round(*a); to_f.round(*a); end unless method_defined?(:round)
  def floor(*a); to_f.floor(*a); end unless method_defined?(:floor)
  def ceil(*a); to_f.ceil(*a); end unless method_defined?(:ceil)
  def truncate(*a); to_f.truncate(*a); end unless method_defined?(:truncate)
  def clamp(lo, hi); self < lo ? lo : (self > hi ? hi : self); end unless method_defined?(:clamp)
end

# Struct.new(..., keyword_init: true)
class Struct
  class << self
    alias_method :__mkxpweb_struct_new, :new unless method_defined?(:__mkxpweb_struct_new)
    def new(*args, &blk)
      return __mkxpweb_struct_new(*args, &blk) unless equal?(Struct) && args.last.is_a?(Hash)
      opts = args.pop
      klass = __mkxpweb_struct_new(*args, &blk)
      if opts[:keyword_init]
        klass.class_eval do
          def initialize(h = {})
            super()
            h.each { |k, v| self[k.to_sym] = v }
          end
        end
      end
      klass
    end
  end
end

$: = [] if $:.nil?
$LOAD_PATH = $: if $LOAD_PATH.nil?
module Kernel
  def require(*a); false; end unless method_defined?(:require) || private_method_defined?(:require)
  def require_relative(*a); false; end unless method_defined?(:require_relative) || private_method_defined?(:require_relative)
end

module Kernel
  # Threads run inline in the web build, so there is nothing to wait for.
  def sleep(*a); 0; end unless method_defined?(:sleep) || private_method_defined?(:sleep)
end

# mkxp-z HTTPLite on the browser's fetch() (native web_http): same signatures and results,
# {status: Integer, body: String, headers: Hash}, MKXPError on connection failure. Browser
# limits: the server must allow CORS, forbidden headers (Host, Content-Length, User-Agent...)
# are dropped, header names come back lowercase, and redirect = false can't see the target
# (status 302, headers {"x-web-opaque-redirect" => "1"}).
module HTTPLite
  # Seconds before a request is aborted (web only; mkxp-z has no equivalent setting).
  @timeout = 30
  # Connectivity probes that never allow CORS (network_available? in DP Scripting Utilities):
  # fail at once instead of making requests that the browser rejects anyway.
  WEB_NO_CORS = %w(www.google.com google.com 1.1.1.1 8.8.8.8 api.github.com)

  class << self
    attr_accessor :timeout

    def get(url, headers = nil, redirect = true)
      __request("GET", url, headers, "", nil, redirect)
    end

    def post(url, post_data, headers = nil, redirect = true)
      body = (post_data || {}).map { |k, v| "#{__form_enc(k)}=#{__form_enc(v)}" }.join("&")
      __request("POST", url, headers, body, "application/x-www-form-urlencoded", redirect)
    end

    def post_body(url, body, content_type, headers = nil)
      __request("POST", url, headers, body.to_s, content_type, true)
    end

    def __form_enc(s)
      out = ""
      s.to_s.each_byte do |b|
        if (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 45 || b == 46 || b == 95 || b == 126
          out << b.chr
        else
          out << sprintf("%%%02X", b)
        end
      end
      out
    end

    def __request(method, url, headers, body, content_type, redirect)
      url = url.to_s
      if url =~ /\Ahttps?:\/\/([^\/:?#]+)[:\/]?\z/i && HTTPLite::WEB_NO_CORS.include?($1.downcase)
        raise MKXPError, "HTTPLite (web): #{url} does not allow cross-origin requests"
      end
      h = {}
      (headers || {}).each { |k, v| h[k.to_s] = v.to_s }
      h["Content-Type"] = content_type.to_s if content_type && h.keys.none? { |k| k.downcase == "content-type" }
      t = (@timeout.to_f * 1000).to_i
      status, hdrs, data = web_http(method, url, HTTPLite::JSON.stringify(h), body.to_s, t, redirect ? true : false)
      raise MKXPError, data if status == 0
      rh = {}
      hdrs.split("\n").each do |l|
        i = l.index(": ")
        rh[l[0, i]] = l[(i + 2)..-1] if i
      end
      { :status => status, :body => data, :headers => rh }
    end
  end

  module JSON
    class ParserError < StandardError; end

    def self.parse(str, *opts)
      p = Parser.new(str.to_s)
      v = p.value
      p.ws
      raise ParserError, "trailing data at #{p.pos}" unless p.eos?
      v
    end

    ESC = { "\"" => "\\\"", "\\" => "\\\\", "\n" => "\\n", "\r" => "\\r", "\t" => "\\t",
            "\b" => "\\b", "\f" => "\\f" }

    # Strings are emitted as UTF-8 (only " \ and control characters are escaped), like
    # Ruby's JSON.generate. The regexp check keeps big payloads (base64) on the fast path.
    def self.__str(s)
      s = s.to_s
      return "\"" + s + "\"" unless s =~ /[\x00-\x1f"\\]/
      "\"" + s.gsub(/[\x00-\x1f"\\]/) { |c| ESC[c] || sprintf("\\u%04x", c.getbyte(0)) } + "\""
    end

    def self.stringify(obj)
      case obj
      when Hash then "{" + obj.map { |k, v| "#{__str(k)}:#{stringify(v)}" }.join(",") + "}"
      when Array then "[" + obj.map { |v| stringify(v) }.join(",") + "]"
      when String, Symbol then __str(obj)
      when nil then "null"
      when true then "true"
      when false then "false"
      when Integer then obj.to_s
      when Float then (obj.nan? || obj.infinite?) ? "null" : obj.to_s
      when Numeric then obj.to_s
      else __str(obj)
      end
    end

    class Parser
      attr_reader :pos
      def initialize(s); @s = s; @pos = 0; @n = s.bytesize; end
      def eos?; @pos >= @n; end
      def peek; @s.getbyte(@pos); end
      def ws
        while !eos? && [32, 9, 10, 13].include?(peek)
          @pos += 1
        end
      end
      def expect(str)
        raise ParserError, "expected #{str} at #{@pos}" unless @s.byteslice(@pos, str.bytesize) == str
        @pos += str.bytesize
      end
      def value
        ws
        raise ParserError, "unexpected end" if eos?
        c = peek
        case c
        when 123 then object       # {
        when 91  then array        # [
        when 34  then string       # "
        when 116 then expect("true"); true
        when 102 then expect("false"); false
        when 110 then expect("null"); nil
        else number
        end
      end
      def object
        @pos += 1; h = {}; ws
        if peek == 125 then @pos += 1; return h; end
        loop do
          ws; k = string; ws; expect(":"); h[k] = value; ws
          c = peek; @pos += 1
          return h if c == 125
          raise ParserError, "expected , or } at #{@pos}" unless c == 44
        end
      end
      def array
        @pos += 1; a = []; ws
        if peek == 93 then @pos += 1; return a; end
        loop do
          a << value; ws
          c = peek; @pos += 1
          return a if c == 93
          raise ParserError, "expected , or ] at #{@pos}" unless c == 44
        end
      end
      # Unescaped runs are copied with String#index (byte offsets: no MRB_UTF8_STRING), so
      # multi-MB values (base64 saves) don't go through a per-byte Ruby loop.
      def string
        raise ParserError, "expected string at #{@pos}" unless peek == 34
        @pos += 1; out = ""
        loop do
          q = @s.index("\"", @pos) or raise ParserError, "unterminated string"
          @bs = (@s.index("\\", @pos) || @n) if @bs.nil? || (@bs < @pos && @bs < @n)
          if q < @bs
            out << @s.byteslice(@pos, q - @pos)
            @pos = q + 1
            return out
          end
          out << @s.byteslice(@pos, @bs - @pos)
          e = @s.getbyte(@bs + 1); @pos = @bs + 2
          case e
          when 110 then out << "\n"
          when 116 then out << "\t"
          when 114 then out << "\r"
          when 98  then out << "\b"
          when 102 then out << "\f"
          when 117
            cp = @s.byteslice(@pos, 4).to_i(16); @pos += 4
            if cp >= 0xD800 && cp <= 0xDBFF && @s.byteslice(@pos, 2) == "\\u"
              lo = @s.byteslice(@pos + 2, 4).to_i(16)
              if lo >= 0xDC00 && lo <= 0xDFFF
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00); @pos += 6
              end
            end
            out << [cp].pack("U")
          when nil then raise ParserError, "unterminated string"
          else out << e.chr
          end
        end
      end
      def number
        st = @pos
        @pos += 1 while !eos? && "+-0123456789.eE".include?(peek.chr)
        t = @s.byteslice(st, @pos - st)
        raise ParserError, "bad token at #{st}" if t.empty?
        (t.include?(".") || t.include?("e") || t.include?("E")) ? t.to_f : t.to_i
      end
    end
  end
end

# The browser FS is case-sensitive, Windows is not: games ask for "Audio/BGM/TITULO"
# while the file is "Titulo.ogg". Resolve misses against the (lowercased) asset mapping.
module Kernel
  def __web_ci(path)
    ps = path.to_s
    return ps if __web_exist_raw?(ps)
    r = (web_resolve_path(ps) rescue nil)
    r ? (ps.start_with?("./") ? "./" + r : r) : ps
  end
  def __web_exist_raw?(ps)
    FileTest.__web_exist?(ps)
  end
end
class FileTest
  class << self
    alias_method :__web_exist?, :exist? unless method_defined?(:__web_exist?)
    alias_method :__web_file?, :file? unless method_defined?(:__web_file?)
    alias_method :__web_directory?, :directory? unless method_defined?(:__web_directory?)
    def exist?(p); __web_exist?(p.to_s) || __web_exist?(__web_ci(p)); end
    def file?(p); __web_file?(p.to_s) || __web_file?(__web_ci(p)); end
    def directory?(p); __web_directory?(p.to_s) || __web_directory?(__web_ci(p)); end
    alias_method :exists?, :exist?
  end
end
class << File
  def exist?(p); FileTest.exist?(p); end
  def file?(p); FileTest.file?(p); end
  def directory?(p); FileTest.directory?(p); end
  alias_method :exists?, :exist?
end

# mruby-io File/IO bypass the web loader: drive.js only writes 1-byte placeholders,
# so fetch the real file first. Writes are persisted to IndexedDB on close.
class << File
  alias_method :__web_open, :open unless method_defined?(:__web_open)
  def open(path, mode = "r", *rest, &blk)
    m = mode.to_s
    writing = m.include?("w") || m.include?("a") || m.include?("+")
    path = __web_ci(path) if !writing
    web_fetch_file(path.to_s) if !writing || m.include?("+")
    return __web_open(path, mode, *rest, &blk) unless blk && writing
    ret = __web_open(path, mode, *rest, &blk)
    save_file_async(path.to_s.sub(/\A\.\//, ""))
    ret
  end
  def read(path, *a)
    open(path, "rb") { |f| f.read }
  end
  alias_method :binread, :read
  def readlines(path, *a)
    out = []
    read(path).each_line { |l| out << l }
    out
  end
  def write(path, data, *a)
    open(path, "wb") { |f| f.write(data) }
    data.to_s.bytesize
  end
  alias_method :binwrite, :write
end

# In mruby Kernel.rand resolves through Object -> Kernel#rand, so a top-level
# `def rand` (Essentials RubyUtilities) shadows it and `oldRand` recurses.
# Pin the C implementations on Kernel's singleton, like MRI's module_function copy.
module Kernel
  class << self
    alias_method :rand, :rand
    alias_method :srand, :srand
  end
end

# ---- Ruby 2.x/3.x core methods missing from mruby 2.1.2 ----
class Integer
  def even?; self % 2 == 0; end unless method_defined?(:even?)
  def odd?; self % 2 == 1; end unless method_defined?(:odd?)
  def pred; self - 1; end unless method_defined?(:pred)
  def succ; self + 1; end unless method_defined?(:succ)
  def pow(e, m = nil); m ? (self ** e) % m : self ** e; end unless method_defined?(:pow)
  def digits(b = 10); n = abs; r = []; loop { r << n % b; n /= b; break if n == 0 }; r; end unless method_defined?(:digits)
  def bit_length; n = self < 0 ? ~self : self; c = 0; while n > 0; n >>= 1; c += 1; end; c; end unless method_defined?(:bit_length)
  def ord; self; end unless method_defined?(:ord)
end
class Numeric
  def positive?; self > 0; end unless method_defined?(:positive?)
  def negative?; self < 0; end unless method_defined?(:negative?)
  def zero?; self == 0; end unless method_defined?(:zero?)
  def nonzero?; self == 0 ? nil : self; end unless method_defined?(:nonzero?)
  def abs2; self * self; end unless method_defined?(:abs2)
end
class Object
  def then; yield self; end unless method_defined?(:then)
  def yield_self; yield self; end unless method_defined?(:yield_self)
  def itself; self; end unless method_defined?(:itself)
end
module Enumerable
  def sum(init = 0); s = init; each { |x| s += block_given? ? yield(x) : x }; s; end unless method_defined?(:sum)
  def filter_map; r = []; each { |x| v = yield(x); r << v if v }; r; end unless method_defined?(:filter_map)
  def tally; h = {}; each { |x| h[x] = (h[x] || 0) + 1 }; h; end unless method_defined?(:tally)
  def each_entry(&b); each(&b); end unless method_defined?(:each_entry)
  def filter(&b); select(&b); end unless method_defined?(:filter)
end
class Array
  def sum(init = 0); s = init; each { |x| s += block_given? ? yield(x) : x }; s; end unless method_defined?(:sum)
  def filter_map; r = []; each { |x| v = yield(x); r << v if v }; r; end unless method_defined?(:filter_map)
  def tally; h = {}; each { |x| h[x] = (h[x] || 0) + 1 }; h; end unless method_defined?(:tally)
  def filter(&b); select(&b); end unless method_defined?(:filter)
  def filter!(&b); select!(&b); end unless method_defined?(:filter!)
  def union(*o); (self + o.flatten(1)).uniq; end unless method_defined?(:union)
  def difference(*o); r = self; o.each { |x| r -= x }; r; end unless method_defined?(:difference)
  def intersection(*o); r = self; o.each { |x| r &= x }; r; end unless method_defined?(:intersection)
  def intersect?(o); !(self & o).empty?; end unless method_defined?(:intersect?)
end
class Hash
  def filter(&b); select(&b); end unless method_defined?(:filter)
  def filter_map; r = []; each { |k, v| x = yield(k, v); r << x if x }; r; end unless method_defined?(:filter_map)
  def sum(init = 0); s = init; each { |k, v| s += yield(k, v) }; s; end unless method_defined?(:sum)
  def transform_values; h = {}; each { |k, v| h[k] = yield(v) }; h; end unless method_defined?(:transform_values)
  def transform_keys; h = {}; each { |k, v| h[yield(k)] = v }; h; end unless method_defined?(:transform_keys)
  def transform_values!; keys.each { |k| self[k] = yield(self[k]) }; self; end unless method_defined?(:transform_values!)
  def to_h; return dup unless block_given?; h = {}; each { |k, v| a, b = yield(k, v); h[a] = b }; h; end
  def any?; return !empty? unless block_given?; each { |k, v| return true if yield(k, v) }; false; end
  def sort_by(&b); to_a.sort_by(&b); end unless method_defined?(:sort_by)
  def min_by(&b); to_a.min_by(&b); end unless method_defined?(:min_by)
  def max_by(&b); to_a.max_by(&b); end unless method_defined?(:max_by)
  def sum_values; values.sum; end
  def dig(k, *r); v = self[k]; r.empty? || v.nil? ? v : v.dig(*r); end unless method_defined?(:dig)
end
class String
  def match?(re, pos = 0); !!(re.is_a?(String) ? index(re, pos) : re.match(self[pos..-1] || "")); end unless method_defined?(:match?)
  def delete_prefix(p); start_with?(p) ? self[p.size..-1] : dup; end unless method_defined?(:delete_prefix)
  def delete_suffix(s); end_with?(s) ? self[0, size - s.size] : dup; end unless method_defined?(:delete_suffix)
  def casecmp?(o); downcase == o.to_s.downcase; end unless method_defined?(:casecmp?)
  def casecmp(o); downcase <=> o.to_s.downcase; end unless method_defined?(:casecmp)
  def unpack1(f); unpack(f)[0]; end unless method_defined?(:unpack1)
  def squeeze(*a); gsub(/(.)\1+/) { $1 }; end unless method_defined?(:squeeze)
end
class Symbol
  def start_with?(*a); to_s.start_with?(*a); end unless method_defined?(:start_with?)
  def end_with?(*a); to_s.end_with?(*a); end unless method_defined?(:end_with?)
  def upcase; to_s.upcase.to_sym; end unless method_defined?(:upcase)
  def downcase; to_s.downcase.to_sym; end unless method_defined?(:downcase)
  def capitalize; to_s.capitalize.to_sym; end unless method_defined?(:capitalize)
  def [](*a); to_s[*a]; end unless method_defined?(:[])
end

# mkxp-z animated-bitmap API: this engine has no animated GIF bitmaps, every bitmap is static.
class Bitmap
  def animated?; false; end unless method_defined?(:animated?)
  def playing; false; end unless method_defined?(:playing)
  def playing=(v); end unless method_defined?(:playing=)
  def play; nil; end unless method_defined?(:play)
  def stop; nil; end unless method_defined?(:stop)
  def goto_and_stop(i); nil; end unless method_defined?(:goto_and_stop)
  def goto_and_play(i); nil; end unless method_defined?(:goto_and_play)
  def next_frame; nil; end unless method_defined?(:next_frame)
  def previous_frame; nil; end unless method_defined?(:previous_frame)
  def frame_count; 1; end unless method_defined?(:frame_count)
  def current_frame; 0; end unless method_defined?(:current_frame)
  def frame_rate; 0; end unless method_defined?(:frame_rate)
  def frame_rate=(v); end unless method_defined?(:frame_rate=)
  def looping; true; end unless method_defined?(:looping)
  def looping=(v); end unless method_defined?(:looping=)
end

# mkxp-z Sprite pattern overlay: stored but not rendered by this engine.
class Sprite
  [:pattern, :pattern_blend_type, :pattern_tile, :pattern_opacity, :pattern_scroll_x,
   :pattern_scroll_y, :pattern_zoom_x, :pattern_zoom_y, :invert].each do |a|
    attr_accessor a unless method_defined?(a)
  end
end

module System
  def self.power_state; { :discharging => false, :seconds => nil, :percent => nil }; end
end

# mkxp-z runs Essentials at the display refresh rate ("syncToRefreshrate"); RGSS1 defaults to 40.
Graphics.frame_rate = 60

# Multi Save rescues Marshal::RestoreError and reads File.mtime for its info-box cache.
module Marshal
  class RestoreError < StandardError; end unless const_defined?(:RestoreError)
end
class << File
  def mtime(p); File.open(p, "rb") { |f| f.mtime }; end unless method_defined?(:mtime)
end
# mruby-io File.basename takes no suffix argument (Ruby: basename(path, ".ext") / ".*").
class << File
  alias_method :__web_basename, :basename unless method_defined?(:__web_basename)
  def basename(path, suffix = nil)
    b = __web_basename(path.to_s)
    return b unless suffix
    if suffix == ".*"
      i = b.rindex(".")
      (i && i > 0) ? b[0...i] : b
    elsif b.end_with?(suffix) && b != suffix
      b[0...(b.size - suffix.size)]
    else
      b
    end
  end
end

# Ruby 2+ accepts nested paths in const_get / const_defined? ("Battle::Move::None");
# mruby raises "wrong constant name". Walk the path one segment at a time.
class Module
  alias_method :__web_const_get, :const_get unless method_defined?(:__web_const_get)
  alias_method :__web_const_defined?, :const_defined? unless method_defined?(:__web_const_defined?)
  def const_get(name, *a)
    n = name.to_s
    return __web_const_get(name, *a) unless n.include?("::")
    n.sub(/\A::/, "").split("::").inject(n.start_with?("::") ? Object : self) { |m, c| m.__web_const_get(c.to_sym, *a) }
  end
  def const_defined?(name, *a)
    n = name.to_s
    return __web_const_defined?(name, *a) unless n.include?("::")
    m = n.start_with?("::") ? Object : self
    n.sub(/\A::/, "").split("::").each do |c|
      return false unless m.is_a?(Module) && m.__web_const_defined?(c.to_sym, *a)
      m = m.__web_const_get(c.to_sym)
    end
    true
  end
end

# `defined?(super)` (rewritten by build_scripts.rb): is there another definition of the
# current method further up the ancestor chain? (Approximate: assumes the running method
# is the first definition found, which holds for the prepend/alias hook patterns plugins use.)
module Kernel
  def __defsuper(m)
    return nil unless m
    anc = (singleton_class.ancestors rescue self.class.ancestors)
    found = false
    anc.each do |mod|
      has = mod.instance_methods(false).include?(m) ||
            ((mod.private_instance_methods(false).include?(m)) rescue false)
      next unless has
      return "super" if found
      found = true
    end
    nil
  end
end
