# Dump Data/PluginScripts.rxdata to plugins_src/<NNN_plugin>/<file> for grepping.
require 'zlib'
require 'fileutils'
Marshal.load(File.binread(ARGV[0])).each_with_index do |(name, _meta, scripts), i|
  dir = File.join(ARGV[1], format('%03d_%s', i, name.gsub(/[^\w\-]+/, '_')))
  FileUtils.mkdir_p(dir)
  scripts.each { |f, c| File.binwrite(File.join(dir, f.tr('\/', '__')), Zlib::Inflate.inflate(c)) }
end
puts 'ok'
