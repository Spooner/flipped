require 'rake/rdoctask'
require 'spec/rake/spectask'
require 'rake/clean'
require 'fileutils'
include FileUtils

RELEASE_VERSION = '0.2.0'

OCRA = 'ruby build/ocrasa.rb'

RDOC_DIR = File.join('doc', 'rdoc')
BINARY_DIR = 'bin'

SOURCE_DIR = 'lib'
APP = 'flipped'
APP_EXE = File.join(BINARY_DIR, "#{APP}.exe")

RELEASE_DIR = File.join("release", "#{APP}_v#{RELEASE_VERSION.gsub(/\./, '_')}")
RELEASE_PACKAGE_7Z = "#{RELEASE_DIR}.7z"
RELEASE_PACKAGE_ZIP = "#{RELEASE_DIR}.zip"

CLOBBER.include FileList[RDOC_DIR], RELEASE_PACKAGE_7Z, RELEASE_PACKAGE_ZIP
CLEAN.include APP_EXE, RELEASE_DIR

namespace :rdoc do
  Rake::RDocTask.new do |rdoc|
    rdoc.rdoc_dir = RDOC_DIR
    rdoc.options << '--line-numbers'
    rdoc.rdoc_files.add(%w(*.rdoc doc/*.rdoc lib/**/*.rb))
    rdoc.title = 'Flipped - The SiD flip-book tool'
  end
end

# Optional if you have rspec installed.

Spec::Rake::SpecTask.new do |t|
  t.spec_files = FileList['spec/**/*_spec.rb']
end

namespace :compile do
  # ------------------------------------------------------------------------------
  desc 'Compile #{APP} executable'

  task APP => APP_EXE
  
  prerequisites = FileList["lib/#{APP}.rb*", "lib/#{APP}/**/*.rb"]
  file APP_EXE => prerequisites do |t|
    puts "Creating exe using #{OCRA}"
    system "#{OCRA} #{prerequisites.join(' ')} --console"
    mkdir_p BINARY_DIR
    move "lib/#{APP}.exe", APP_EXE
    puts 'Done.'
  end
end

namespace :build do
  file RELEASE_DIR do
    mkdir_p RELEASE_DIR
  end

  desc "Release 7z"
  task :"7z" => RELEASE_PACKAGE_7Z
  file RELEASE_PACKAGE_7Z => RELEASE_DIR do
    puts "Making #{RELEASE_PACKAGE_7Z}"
    rm RELEASE_PACKAGE_7Z if File.exist? RELEASE_PACKAGE_7Z
    cd 'release'
    puts %x[7z a "#{RELEASE_PACKAGE_7Z.sub('release/', '')}" "#{RELEASE_DIR.sub('release/', '')}"]
    cd '..'
  end

  desc "Release Zip"
  task :zip => RELEASE_PACKAGE_ZIP
  file RELEASE_PACKAGE_ZIP => RELEASE_DIR do
    puts "Making #{RELEASE_PACKAGE_ZIP}"
    rm RELEASE_PACKAGE_ZIP if File.exist? RELEASE_PACKAGE_ZIP
    cd 'release'
    puts %x[7z a -tzip "#{RELEASE_PACKAGE_ZIP.sub('release/', '')}" "#{RELEASE_DIR.sub('release/', '')}"]
    cd '..'
  end

  task :compress => [:zip, :"7z"]

  desc 'Make full #{APP.capitalize} release'
  task :release => :compress
end

desc "Install libraries required by Flipped"
task :install_libraries do
  load 'install_libraries.rb'
end

require 'build/package'
