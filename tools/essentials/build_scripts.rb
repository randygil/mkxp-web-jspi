# Build a web Scripts.rxdata for a Pokemon Essentials (v20/v21) game:
#   base sections (scripts_src) + every plugin script inlined before "Main",
#   with generic mruby rewrites (defined?) and porting patches (patches.rb) applied
#   by section/file name.
# usage (in container): ruby build_scripts.rb <scripts_src> <PluginScripts.rxdata> <patches.rb> <out.rxdata>
require 'zlib'
require 'json'

src, plugins_path, patches_path, out = ARGV
PATCHES = []
def patch(name_re, from, to, opts = {})
  PATCHES << [name_re, from, to, opts]
end
load patches_path

# mruby 2.1.2 has no `defined?` keyword: rewrite each use to an equivalent runtime check.
DEFINED_RE = /(?<![\w.])defined\?\s*\(\s*([^()]*(?:\([^()]*\))?[^()]*?)\s*\)/
$defined_stats = Hash.new(0)
def rewrite_defined(code)
  # eval("defined?(Const#{x})") -> __defc("Const#{x}")
  code = code.gsub(/eval\("defined\?\(([A-Z]\w*#\{[^}]*\}\w*)\)"\)/) { "__defc(\"#{$1}\")" }
  code.gsub(DEFINED_RE) do
    whole, e = $&, $1
    r = case e
        when /\#\{/ then nil                                   # inside a string template: leave
        when /\A(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\z/ then "__defc(#{e.sub(/\A::/, '').inspect})"
        when /\A@\w+\z/ then "(instance_variable_defined?(:#{e}) ? 'instance-variable' : nil)"
        when /\A\$\w+\z/ then "(#{e}.nil? ? nil : 'global-variable')"
        when 'super' then "__defsuper(__method__)"
        when 'yield' then "(block_given? ? 'yield' : nil)"
        when /\A[a-z_]\w*[?!]?\z/ then "(respond_to?(:#{e}, true) ? 'method' : nil)"
        when /\A(.+)\.(\w+[?!=]?)(?:\(.*\))?\z/m
          recv, meth = $1, $2
          "(begin; (#{recv}).respond_to?(:#{meth}, true) ? 'method' : nil; rescue Exception; nil; end)"
        end
    $defined_stats[r ? :rewritten : :left] += 1
    warn "defined? left as-is: #{whole}" unless r
    r || whole
  end
end

used = Hash.new(0)
apply = lambda do |name, code|
  code = rewrite_defined(code.gsub("\r\n", "\n"))
  PATCHES.each_with_index do |(re, from, to, opts), i|
    next unless name =~ re
    n = 0
    if from.is_a?(Regexp)
      code = code.gsub(from) { n += 1; to.is_a?(Proc) ? to.call($~) : to }
    else
      pos = 0
      while (idx = code.index(from, pos))
        code = code[0...idx] + to + code[(idx + from.size)..-1]; n += 1
        pos = idx + to.size
        break if opts[:once]
      end
    end
    used[i] += n
  end
  code
end

index = JSON.parse(File.read(File.join(src, 'index.json')))
base = index.map do |h|
  code = File.binread(File.join(src, h['file'])).force_encoding('UTF-8')
  [h['magic'], h['name'], apply.call(h['name'], code)]
end

plugin_secs = []
Marshal.load(File.binread(plugins_path)).each do |name, meta, scripts|
  next if meta[:disabled] && %w[true verdadero si x].include?(meta[:disabled].to_s.downcase)
  meta_s = meta.inspect
  # register the plugin (metadata only) exactly like PluginManager.runPlugins would
  plugin_secs << [0, "[#{name}] <register>", "PluginManager.register(#{meta_s})\n"]
  scripts.each do |fname, deflated|
    code = Zlib::Inflate.inflate(deflated).force_encoding('UTF-8').gsub("\t", '  ')
    sname = "[#{name}] #{fname.gsub('\\', '/').split('/')[-1]}"
    plugin_secs << [0, sname, apply.call(sname, code)]
  end
end

# Debug aid: SPLIT=<section name> splits that section at top-level `#====` banners
# so the engine's load trace pinpoints the failing chunk.
if (sp = ENV['SPLIT']) && !sp.empty?
  base = base.flat_map do |m, n, c|
    next [[m, n, c]] unless n == sp
    parts = c.split(/^(?=#={10,}\s*$\n(?!#={10,}))/)
    parts.each_with_index.map { |p, i| [m, "#{n}##{i}", p] }
  end
end

main_i = base.rindex { |_, n, _| n == 'Main' } or abort 'no Main section'
all = base[0...main_i] + plugin_secs + base[main_i..-1]
arr = all.map { |m, n, c| [m, n, Zlib::Deflate.deflate(c)] }
File.binwrite(out, Marshal.dump(arr))
PATCHES.each_with_index { |(re, from, _), i| warn "UNUSED patch #{i}: #{re.inspect} #{from.inspect[0, 60]}" if used[i] == 0 }
puts "defined? rewrites: #{$defined_stats.inspect}"
puts "Wrote #{arr.size} sections (#{plugin_secs.size} plugin) to #{out}"
