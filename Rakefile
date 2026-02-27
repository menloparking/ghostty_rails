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

task default: :test
