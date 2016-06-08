require 'optparse'
require 'open3'
require 'json'

require_relative 'xamarin-builder/builder'

# -----------------------
# --- Constants
# -----------------------
@work_dir = ENV['BITRISE_SOURCE_DIR']
@result_log_path = File.join(@work_dir, 'TestResult.xml')

# -----------------------
# --- Functions
# -----------------------

def log_info(message)
  puts
  puts "\e[34m#{message}\e[0m"
end

def log_details(message)
  puts "  #{message}"
end

def log_done(message)
  puts "  \e[32m#{message}\e[0m"
end

def log_warning(message)
  puts "\e[33m#{message}\e[0m"
end

def log_error(message)
  puts "\e[31m#{message}\e[0m"
end

def log_fail(message)
  system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value failed')

  puts "\e[31m#{message}\e[0m"
  exit(1)
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
  async: 'yes',
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
  opts.on('-y', '--async async', 'Async') { |y| options[:async] = y unless y.to_s == '' }
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
log_info 'Configs:'
log_details("* project: #{options[:project]}")
log_details("* configuration: #{options[:configuration]}")
log_details("* platform: #{options[:platform]}")
log_details('* api_key: ***')
log_details("* user: #{options[:user]}")
log_details("* devices: #{options[:devices]}")
log_details("* async: #{options[:async]}")
log_details("* series: #{options[:series]}")
log_details("* parallelization: #{options[:parallelization]}")
log_details('* sign_parameters: ***')
log_details("* other_parameters: #{options[:other_parameters]}")

#
# Validate options
log_fail('No project file found') unless options[:project] && File.exist?(options[:project])
log_fail('configuration not specified') unless options[:configuration]
log_fail('platform not specified') unless options[:platform]
log_fail('api_key not specified') unless options[:api_key]
log_fail('user not specified') unless options[:user]
log_fail('devices not specified') unless options[:devices]
log_fail('series not specified') unless options[:series]

#
# Main

builder = Builder.new(options[:project], options[:configuration], options[:platform], "android")
begin
  builder.build
  builder.build_test
rescue => ex
  log_error(ex.inspect.to_s)
  log_error('--- Stack trace: ---')
  log_fail(ex.backtrace.to_s)
end

output = builder.generated_files
log_fail 'No output generated' if output.nil? || output.empty?

any_uitest_built = false

output.each do |_, project_output|
  next if project_output[:apk].nil? || project_output[:uitests].nil? || project_output[:uitests].empty?

  apk_path = project_output[:apk]
  log_fail('no generated apk found') unless apk_path

  project_output[:uitests].each do |dll_path|
    any_uitest_built = true

    assembly_dir = File.dirname(dll_path)

    log_info("Uploading #{apk_path} with #{dll_path}")

    #
    # Get test cloud path
    test_cloud = Dir[File.join(@work_dir, '/**/packages/Xamarin.UITest.*/tools/test-cloud.exe')].last
    log_fail("Can't find test-cloud.exe") unless test_cloud

    #
    # Build Request
    request = ['mono', "\"#{test_cloud}\"", 'submit', "\"#{apk_path}\"", options[:api_key]]
    request << options[:sign_parameters] if options[:sign_parameters]
    request << "--user #{options[:user]}"
    request << "--assembly-dir \"#{assembly_dir}\""
    request << "--devices #{options[:devices]}"
    request << '--async-json' if options[:async] == 'yes'
    request << "--series #{options[:series]}" if options[:series]
    request << "--nunit-xml #{@result_log_path}"
    request << '--fixture-chunk' if options[:parallelization] == 'by_test_fixture'
    request << '--test-chunk' if options[:parallelization] == 'by_test_chunk'
    request << options[:other_parameters]

    log_details(request.join(' '))
    puts

    #
    # Run Test Cloud Upload
    captured_stdout_err_lines = []
    success = Open3.popen2e(request.join(' ')) do |stdin, stdout_err, wait_thr|
      stdin.close

      while line = stdout_err.gets
        puts line
        captured_stdout_err_lines << line
      end

      wait_thr.value.success?
    end

    puts

    #
    # Process output
    result_log = ''
    if File.exist? @result_log_path
      file = File.open(@result_log_path)
      result_log = file.read
      file.close

      system("envman add --key BITRISE_XAMARIN_TEST_FULL_RESULTS_TEXT --value \"#{result_log}\"") if result_log.to_s != ''
      log_details "Logs are available at path: #{@result_log_path}"
      puts
    end

    unless success
      puts
      puts result_log
      puts

      log_fail('Xamarin Test Cloud failed')
    end

    #
    # Set output envs
    if options[:async] == 'yes'
      captured_stdout_err = captured_stdout_err_lines.join('')

      test_run_id_regexp = /"TestRunId":"(?<id>.*)",/
      test_run_id = ''

      match = captured_stdout_err.match(test_run_id_regexp)
      if match
        captures = match.captures
        test_run_id = captures[0] if captures && captures.length == 1

        if test_run_id.to_s != ''
          system("envman add --key BITRISE_XAMARIN_TEST_TO_RUN_ID --value \"#{test_run_id}\"")
          log_details "Found Test Run ID: #{test_run_id}"
        end
      end

      error_messages_regexp = /"ErrorMessages":\[(?<error>.*)\],/
      error_messages = ''

      match = captured_stdout_err.match(error_messages_regexp)
      if match
        captures = match.captures
        error_messages = captures[0] if captures && captures.length == 1

        if error_messages.to_s != ''
          log_fail("Xamarin Test Cloud submit failed, with error(s): #{error_messages}")
        end
      end
    end

    system('envman add --key BITRISE_XAMARIN_TEST_RESULT --value succeeded')
    log_done('Xamarin Test Cloud submit succeeded')
  end
end

unless any_uitest_built
  puts "generated_files: #{output}"
  log_fail 'No APK or built UITest found in outputs'
end
