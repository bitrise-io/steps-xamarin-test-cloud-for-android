require 'optparse'
require 'pathname'

require_relative 'xamarin-builder/builder'

# -----------------------
# --- Constants
# -----------------------
@work_dir = ENV['BITRISE_SOURCE_DIR']
@result_log_path = File.join(@work_dir, 'TestResult.xml')

# -----------------------
# --- Functions
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

# -----------------------
# --- Main
# -----------------------

#
# Parse options
options = {
  project: nil,
  configuration: nil,
  platform: nil,
  api_key: nil,
  user: nil,
  devices: nil,
  async: true,
  series: 'master',
  parallelization: nil,
  sign_parameters: nil,
  other_parameters: nil
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: step.rb [options]'
  opts.on('-s', '--project path', 'Project path') { |s| options[:project] = s unless s.to_s == '' }
  opts.on('-c', '--configuration config', 'Configuration') { |c| options[:configuration] = c unless c.to_s == '' }
  opts.on('-p', '--platform platform', 'Platform') { |p| options[:platform] = p unless p.to_s == '' }
  opts.on('-a', '--api key', 'Api key') { |a| options[:api_key] = a unless a.to_s == '' }
  opts.on('-u', '--user user', 'User') { |u| options[:user] = u unless u.to_s == '' }
  opts.on('-d', '--devices devices', 'Devices') { |d| options[:devices] = d unless d.to_s == '' }
  opts.on('-y', '--async async', 'Async') { |y| options[:async] = false unless to_bool(y) }
  opts.on('-r', '--series series', 'Series') { |r| options[:series] = r unless r.to_s == '' }
  opts.on('-l', '--parallelization parallelization', 'Parallelization') { |l| options[:parallelization] = l unless l.to_s == '' }
  opts.on('-g', '--sign parameters', 'Sign') { |g| options[:sign_parameters] = g unless g.to_s == '' }
  opts.on('-m', '--other parameters', 'Other') { |m| options[:other_parameters] = m unless m.to_s == '' }
  opts.on('-h', '--help', 'Displays Help') do
    exit
  end
end
parser.parse!

#
# Print options
puts
puts '========== Configs =========='
puts " * project: #{options[:project]}"
puts " * configuration: #{options[:configuration]}"
puts " * platform: #{options[:platform]}"
puts ' * api_key: ***'
puts " * user: #{options[:user]}"
puts " * devices: #{options[:devices]}"
puts " * async: #{options[:async]}"
puts " * series: #{options[:series]}"
puts " * parallelization: #{options[:parallelization]}"
puts ' * sign_parameters: ***'
puts " * other_parameters: #{options[:other_parameters]}"

#
# Validate options
fail_with_message('No project file found') unless options[:project] && File.exist?(options[:project])
fail_with_message('configuration not specified') unless options[:configuration]
fail_with_message('platform not specified') unless options[:platform]
fail_with_message('api_key not specified') unless options[:api_key]
fail_with_message('user not specified') unless options[:user]
fail_with_message('devices not specified') unless options[:devices]
fail_with_message('series not specified') unless options[:series]

#
# Main

builder = Builder.new(options[:project], options[:configuration], options[:platform], "android")
begin
  builder.build
  builder.build_test
rescue => ex
  error_with_message(ex.inspect.to_s)
  error_with_message('--- Stack trace: ---')
  error_with_message(ex.backtrace.to_s)
  exit(1)
end

output = builder.generated_files
fail_with_message 'No output generated' if output.nil? || output.empty?

any_uitest_built = false

output.each do |_, project_output|
  next if project_output[:apk].nil? || project_output[:uitests].nil? || project_output[:uitests].empty?

  apk_path = project_output[:apk]

  project_output[:uitests].each do |dll_path|
    any_uitest_built = true

    assembly_dir = File.dirname(dll_path)

    puts
    puts "\e[34mUploading #{apk_path} with #{dll_path}\e[0m"

    #
    # Get test cloud path
    test_cloud = Dir[File.join(@work_dir, '/**/packages/Xamarin.UITest.*/tools/test-cloud.exe')].last
    fail_with_message("\e[31mCan't find test-cloud.exe\e[0m") unless test_cloud

    #
    # Build Request
    request = ["mono", "\"#{test_cloud}\"", "submit", "\"#{apk_path}\"",  options[:api_key]]
    request << options[:sign_parameters] if options[:sign_parameters]
    request << "--user #{options[:user]}"
    request << "--assembly-dir \"#{assembly_dir}\""
    request << "--devices #{options[:devices]}"
    request << '--async' if options[:async]
    request << "--series #{options[:series]}" if options[:series]
    request << "--nunit-xml #{@result_log_path}"
    request << '--fixture-chunk' if options[:parallelization] == 'by_test_fixture'
    request << '--test-chunk' if options[:parallelization] == 'by_test_chunk'
    request << options[:other_parameters]

    puts "  #{request.join(' ')}"
    system(request.join(' '))
    request_result = $?

    result_log = ''
    if File.exist? @result_log_path
      file = File.open(@result_log_path)
      result_log = file.read
      file.close
    end

    unless request_result.success?
      puts
      puts result_log
      fail_with_message('Xamarin Test Cloud failed')
    end

    #
    # Set output envs
    system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded')
    system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value \"#{result_log}\"") unless result_log.to_s.strip.length == 0

    puts "  \e[32mXamarin Test Cloud deploy succeeded\e[0m"
    puts "  Logs are available at path: #{@result_log_path}"
  end
end

unless any_uitest_built
  puts "generated_files: #{output}"
  fail_with_message 'No APK or built UITest found in outputs'
end
