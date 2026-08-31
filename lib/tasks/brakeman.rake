# lib/tasks/brakeman.rake
namespace :brakeman do
    desc 'Sync fingerprints in config/brakeman.ignore for warnings that still exist (matched by file/check/type), non-interactively'
    task :sync_ignore do
      require 'json'
      require 'open3'
      require 'tempfile'

      ignore_path = File.expand_path('config/brakeman.ignore', Dir.pwd)
      abort "No ignore file at #{ignore_path}" unless File.exist?(ignore_path)

      ignore_data = JSON.parse(File.read(ignore_path))

      report_file = Tempfile.new([ 'brakeman_report', '.json' ])
      stdout, stderr, status = Open3.capture3(
        'bundle', 'exec', 'brakeman', '-f', 'json', '-o', report_file.path, '--no-exit-on-warn', '--no-exit-on-error'
      )
      unless status.success? || File.exist?(report_file.path)
        abort "Brakeman scan failed:\n#{stderr}"
      end

      current = JSON.parse(File.read(report_file.path))['warnings'] || []

      updated = 0
      ignore_data['ignored_warnings'].each do |ignored|
        match = current.find do |w|
          w['file'] == ignored['file'] &&
            w['warning_type'] == ignored['warning_type'] &&
            w['warning_code'] == ignored['warning_code']
        end
        next unless match
        next if match['fingerprint'] == ignored['fingerprint']

        puts "Updating #{ignored['file']} (#{ignored['warning_type']}): " \
             "#{ignored['fingerprint'][0, 8]} -> #{match['fingerprint'][0, 8]}"

        ignored['fingerprint'] = match['fingerprint']
        updated += 1
      end

      File.write(ignore_path, JSON.pretty_generate(ignore_data))
      puts updated.positive? ? "Updated #{updated} fingerprint(s)." : 'No fingerprint changes needed.'
    ensure
      report_file&.close!
    end
  end
