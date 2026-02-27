require "bundler/gem_tasks"
require "rake/testtask"

Dir.glob("lib/tasks/**/*.rake").each do |task|
  load task
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

# Compile TypeScript into dist/ before packaging
# the gem, so consumers get pre-built JS without
# needing a Node toolchain.
task :build_js do
  sh "npm run build"
end
task build: :build_js

task default: :test
