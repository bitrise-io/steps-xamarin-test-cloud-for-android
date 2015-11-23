require 'optparse'
require 'pathname'

@nuget = '/Library/Frameworks/Mono.framework/Versions/Current/bin/nuget'

# -----------------------
# --- functions
# -----------------------

def fail_with_message(message)
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value failed')

  puts "\e[31m#{message}\e[0m"
  exit(1)
end

def error_with_message(message)
  puts "\e[31m#{message}\e[0m"
end

def to_bool(value)
  return true if value == true || value =~ (/^(true|t|yes|y|1)$/i)
  return false if value == false || value.nil? || value == '' || value =~ (/^(false|f|no|n|0)$/i)
  fail_with_message("Invalid value for Boolean: \"#{value}\"")
end

def archive_project!(project_path, configuration, platform, sign_apk)
  # /t:SignAndroidPackage -> generate a signed and unsigned APK
  # /t:PackageForAndroid -> generate a unsigned APK

  # Build project
  output_dir = File.join('bin', platform, configuration)

  params = ['xbuild']
  params << "\"#{project_path}\""
  params << "/p:Configuration=\"#{configuration}\""
  params << "/p:Platform=\"#{platform}\""
  params << "/p:OutputPath=\"#{output_dir}/\""
  params << '/t:SignAndroidPackage' if sign_apk
  params << '/t:PackageForAndroid' unless sign_apk

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  # Get the build path
  project_directory = File.dirname(project_path)
  build_path = File.join(project_directory, output_dir)

  apk_path = Dir[File.join(build_path, '/**/*.apk')].first
  return nil unless apk_path

  full_path = Pathname.new(apk_path).realpath.to_s
  return nil unless full_path
  return nil unless File.exist? full_path
  return full_path
end

def build_test_project!(project_path, configuration, platform)
  output_dir = File.join('bin', platform, configuration)

  params = ['xbuild']
  params << "\"#{project_path}\""
  params << '/t:Build'
  params << "/p:Configuration=#{configuration}"
  params << "/p:Platform=\"#{platform}\""
  params << "/p:OutputPath=\"#{output_dir}/\""

  # Build project
  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Build failed') unless $?.success?

  # Get the build path
  project_directory = File.dirname(project_path)
  File.join(project_directory, output_dir)
end

def clean_project!(project_path, configuration)
  # clean project
  params = ['xbuild']
  params << "\"#{project_path}\""
  params << '/t:Clean'
  params << "/p:Configuration=\"#{configuration}\""

  puts "#{params.join(' ')}"
  system("#{params.join(' ')}")
  fail_with_message('Clean failed') unless $?.success?
end

# -----------------------
# --- main
# -----------------------

#
# Input validation
options = {
  project: nil,
  test_project: nil,
  configuration: nil,
  platform: nil,
  clean_build: true,
  api_key: nil,
  user: nil,
  devices: nil,
  async: true,
  series: 'master',
  parallelization: nil,
  sign_parameters: nil,
  other_parameters: nil
}

parser = OptionParser.new do|opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-t', '--test project', 'Test project') { |t| options[:test_project] = t unless t.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-i', '--clean build', 'Clean build') { |i| options[:clean_build] = false if to_bool(i) == false }
  opts.on('-a', '--api key', 'Api key') { |a| options[:api_key] = a unless a.to_s == '' }
  opts.on('-u', '--user user', 'User') { |u| options[:user] = u unless u.to_s == '' }
  opts.on('-d', '--devices devices', 'Devices') { |d| options[:devices] = d unless d.to_s == '' }
  opts.on('-y', '--async async', 'Async') { |y| options[:async] = false if to_bool(y) == false }
  opts.on('-r', '--series series', 'Series') { |r| options[:series] = r unless r.to_s == '' }
  opts.on('-l', '--parallelization parallelization', 'Parallelization') { |l| options[:parallelization] = l unless l.to_s == '' }
  opts.on('-g', '--sign parameters', 'Sign') { |g| options[:sign_parameters] = g unless g.to_s == '' }
  opts.on('-m', '--other parameters', 'Other') { |m| options[:other_parameters] = m unless m.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('No test_project file found') unless options[:test_project] && File.exist?(options[:test_project])
fail_with_message('configuration not specified') unless options[:configuration]
fail_with_message('platform not specified') unless options[:platform]
fail_with_message('api_key not specified') unless options[:api_key]
fail_with_message('user not specified') unless options[:user]
fail_with_message('devices not specified') unless options[:devices]
fail_with_message('series not specified') unless options[:series]

#
# Print configs
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * test_project: #{options[:test_project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts " * clean_build: #{options[:clean_build]}"
puts ' * api_key: ***'
puts " * user: #{options[:user]}"
puts " * devices: #{options[:devices]}"
puts " * async: #{options[:async]}"
puts " * series: #{options[:series]}"
puts " * parallelization: #{options[:parallelization]}"
puts ' * sign_parameters: ***'
puts " * other_parameters: #{options[:other_parameters]}"

if options[:clean_build]
  #
  # Cleaning the project
  puts
  puts "==> Cleaning project: #{options[:project]}"
  clean_project!(options[:project], options[:configuration])

  puts
  puts "==> Cleaning test project: #{options[:test_project]}"
  clean_project!(options[:test_project], options[:configuration])
end

#
# Archive project
sign_apk = true
sign_apk = false if options[:sign_parameters]
sign_apk = false if options[:other_parameters] && options[:other_parameters].include?('--sign-info')

puts
puts "==> Archive project: #{options[:project]}"
apk_path = archive_project!(options[:project], options[:configuration], options[:platform], sign_apk)
fail_with_message('Failed to locate apk path') unless apk_path && File.exist?(apk_path)
puts "  (i) apk_path path: #{apk_path}"

#
# Build UITest
puts
puts "==> Building test project: #{options[:test_project]}"
assembly_dir = build_test_project!(options[:test_project], options[:configuration], options[:platform])
fail_with_message('failed to get test assembly path') unless assembly_dir && File.exist?(assembly_dir)

#
# Get test cloud path
project_dir = File.dirname(options[:project])
root_dir = File.dirname(project_dir)
test_clouds = Dir[File.join(root_dir, 'packages/Xamarin.UITest.*/tools/test-cloud.exe')]
fail_with_message('No test-cloud.exe found') unless test_clouds && !test_clouds.empty?
fail_with_message('No test-cloud.exe found') unless File.exist?(test_clouds.first)
test_cloud = test_clouds.first
puts "  (i) test_cloud path: #{test_cloud}"

work_dir = ENV['BITRISE_SOURCE_DIR']
result_log = File.join(work_dir, 'TestResult.xml')

#
# Build Request
request = "mono #{test_cloud} submit #{apk_path} #{options[:api_key]}" unless options[:sign_parameters]
request = "mono #{test_cloud} submit #{apk_path} #{options[:api_key]} #{options[:sign_parameters]}" if options[:sign_parameters]
request += " --user #{options[:user]}"
request += " --assembly-dir #{assembly_dir}"
request += " --devices #{options[:devices]}"
request += ' --async' if options[:async]
request += " --series #{options[:series]}" if options[:series]
request += " --nunit-xml #{result_log}"
if options[:parallelization]
  request += ' --fixture-chunk' if options[:parallelization] == 'by_test_fixture'
  request += ' --test-chunk' if options[:parallelization] == 'by_test_chunk'
end
request += " #{options[:other_parameters]}"

puts
puts "request: #{request}"
system(request)
test_success = $?.success?

if test_success
  puts
  puts '(i) The result is: succeeded'
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded') if work_dir

  puts
  puts "(i) The test log is available at: #{result_log}"
  system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{result_log}") if work_dir
else
  puts
  puts "(i) The test log is available at: #{result_log}"
  system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value #{result_log}") if work_dir

  fail_with_message('test failed')
end
