# mruby porting patches for Pokemon Essentials games. patch(section_name_regexp, from, to)
# `from` may be a String (all occurrences) or Regexp. build_scripts.rb warns about
# UNUSED patches, so game/plugin-specific entries are harmless for other games.
# Generic rules match every section (//); the plugin-specific ones were found porting
# Pokemon Anil (plugins: Cable Club, DP Scripting Utilities, v21.1 Hotfixes).

# --- Plugins are inlined into Scripts.rxdata by build_scripts.rb; runPlugins
#     must not recompile (Dir/mtime) or eval (mruby eval has no Binding).
patch(/\APluginManager\z/, "  def self.runPlugins\n", <<~RUBY)
  def self.runPlugins
    Console.echoln_li("Plugins precargados (web)")
    return
  end

  def self.runPlugins_original
RUBY

# --- syntax: squiggly heredoc (Ruby 2.3+)
patch(/Cable Club\] 004_Base_de_datos_sets/, "<<~SETS", "<<-SETS")
# --- syntax: `**nil` (Ruby 2.7+ "no keywords")
patch(/DP Scripting Utilities\] set\.rb/, "def merge(*enums, **nil)", "def merge(*enums)")
# --- constant re-assignment via +=
patch(/v21\.1 Hotfixes\] Misc bug fixes/, 'Essentials::ERROR_TEXT += "', 'Essentials::ERROR_TEXT << "')

# --- mruby-io defines FileTest as a *class*; reopening it as a module crashes the VM
patch(//, /^(\s*)module FileTest\b/, proc { |m| "#{m[1]}class FileTest" })

# --- bare `module_function` (no args) is a no-op in mruby 2.1.2 -> `extend self`
patch(//, /^(\s*)module_function[ \t]*(#.*)?$/, proc { |m| "#{m[1]}extend self" })

# --- 6k-line heredoc -> "too big code block"; emit a single string literal instead
patch(/Cable Club\] 004_Base_de_datos_sets/, /\ASHOWDOWN_RAW_SETS = <<-SETS\n(.*)^SETS\s*\z/m,
      proc { |m| "SHOWDOWN_RAW_SETS = [\n" + m[1].scan(/.{1,8000}/m).map(&:inspect).join(",\n") + "\n].join\n" })

# --- UTF-8 BOM at file start is parsed as a method call by mruby
patch(//, /\A﻿/, "")

# --- `class X < X` (superclass mismatch) crashes the mruby VM; it just means "reopen X"
patch(//, /^(\s*)class\s+(\w+)\s*<\s*\2\s*$/, proc { |m| "#{m[1]}class #{m[2]}" })

# --- mruby never sets `$!`: bind the exception explicitly in rescue clauses
patch(//, /\A(?=.*\$!(?!"))(.*)\z/m, proc { |m|
  m[1].gsub(/^(\s*rescue\b(?:[ \t]+[A-Z][\w:]*(?:[ \t]*,[ \t]*[A-Z][\w:]*)*)?)[ \t]*(#.*)?$/) { "#{$1} => $mkxp_err #{$2}" }
      .gsub(/(^|[^"])\$!(?!")/) { "#{$1}$mkxp_err" }
})

# --- Trainer/owner IDs are 32-bit unsigned; saves made before mruby got 64-bit Integer
#     hold them as Float. Coerce back to Integer on read.
patch(/\APokemon_Owner\z/, "    def initialize(id, name, gender, language)\n", "    def initialize(id, name, gender, language)\n      id = id.to_i if id.is_a?(Float)\n")
patch(/\APokemon_Owner\z/, "    attr_reader :id\n", "    def id; @id = @id.to_i if @id.is_a?(Float); @id; end\n")
patch(/\ATrainer_Class\z/, "  attr_accessor :id\n", "  attr_writer :id\n  def id; @id = @id.to_i if @id.is_a?(Float); @id; end\n")
